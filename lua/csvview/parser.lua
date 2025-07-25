local util = require("csvview.util")

---@class CsvView.Parser.FieldInfo
---@field start_pos integer 1-based start position of the fields
---@field text string|string[] the text of the field. if the field is a quoted field, it will be a string array.

---
---@class Csvview.Parser.Callbacks
---
--- the callback to be called for each parsed line
--- If the callback returns a new end line number, the parser will continue parsing until that line.
---@field on_line fun(lnum:integer,is_comment:boolean,fields:CsvView.Parser.FieldInfo[], endlnum: integer, terminated:boolean): integer?
---
--- the callback to be called when parsing is done.
--- If an error occurs, the `err` parameter will be a string with the error message.
--- "cancelled" will be passed if the parsing was cancelled.
---@field on_end fun(err?:string)

---@class CsvView.Parser.DelimiterPolicy
---@field match fun(s:string, pos:integer, char:integer, match_count:integer): CsvView.Parser.DelimiterPolicy.MatchState

---@enum CsvView.Parser.DelimiterPolicy.MatchState
local MatchState = {
  NO_MATCH = 0,
  MATCHING = 1,
  MATCH_COMPLETE = 2,
}

--- Plain text delimiter
---@param delim string
---@return CsvView.Parser.DelimiterPolicy
local function plain_text_delimiter(delim)
  local delim_len = #delim
  local delim_bytes = { string.byte(delim, 1, delim_len) }
  return { ---@type CsvView.Parser.DelimiterPolicy
    match = function(_, _, char, match_count)
      if char == delim_bytes[match_count + 1] then
        return match_count + 1 == delim_len and MatchState.MATCH_COMPLETE or MatchState.MATCHING
      else
        return MatchState.NO_MATCH
      end
    end,
  }
end

--- @class CsvView.Parser.Source
--- @field get_line fun(lnum:integer):string? Function to get a line by line number. lnum is 1-indexed.
--- @field get_line_count fun():integer Function to get the total number of lines in the buffer.

---@class CsvView.Parser
---@field private _quote_char integer Quote character byte.
---@field private _delimiter CsvView.Parser.DelimiterPolicy Delimiter policy.
---@field private _comments string[] Comment prefixes.
---@field private _max_lookahead integer Maximum number of lines to look ahead for multi-line fields.
---@field private _source CsvView.Parser.Source Source for getting lines
local CsvViewParser = {}
CsvViewParser.__index = CsvViewParser

--- Create a new CsvView.Parser.
---@param bufnr integer Buffer number.
---@param opts CsvView.InternalOptions Options for parsing.
---@param quote_char string Quote character
---@param delimiter string Delimiter string.
---@return CsvView.Parser
function CsvViewParser:new(bufnr, opts, quote_char, delimiter)
  local obj = setmetatable({}, self)
  obj._quote_char = quote_char:byte()
  obj._delimiter = plain_text_delimiter(delimiter)
  obj._comments = opts.parser.comments
  obj._max_lookahead = opts.parser.max_lookahead
  obj._source = {
    get_line = function(lnum)
      return vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, true)[1]
    end,
    get_line_count = function()
      return vim.api.nvim_buf_line_count(bufnr)
    end,
  }
  return obj
end

--- Create a new CsvView.Parser from lines.
---@param quote_char integer Quote character byte.
---@param delimiter string Delimiter string.
---@param comments string[] Comment prefixes.
---@param max_lookahead integer Maximum number of lines to look ahead for multi-line fields.
---@param source CsvView.Parser.Source Source for getting lines.
---@return CsvView.Parser
function CsvViewParser:new_with_source(quote_char, delimiter, comments, max_lookahead, source)
  local obj = setmetatable({}, self)
  obj._quote_char = quote_char
  obj._delimiter = plain_text_delimiter(delimiter)
  obj._comments = comments or {}
  obj._max_lookahead = max_lookahead
  obj._source = source
  return obj
end

--- Check if line is a comment
---@param line string
---@return boolean
function CsvViewParser:_is_comment_line(line)
  for _, comment in ipairs(self._comments) do
    if vim.startswith(line, comment) then
      return true
    end
  end
  return false
end

--- Parse CSV logical line.
---@param lnum integer 1-indexed line number.
---@return boolean is_comment_line Whether the line is a comment line.
---@return CsvView.Parser.FieldInfo[] fields An array of field information.
---@return integer endlnum The end line number.
---@return boolean terminated Whether the closing quote was found within the lookahead limit.
function CsvViewParser:parse_line(lnum)
  -- Assume CSV format compliant with RFC 4180
  -- - Each record is separated by a newline or delimiter.
  -- - If a field contains commas or newlines, enclose it in quote characters.
  -- - If a field contains quote characters, escape them by doubling the quote characters.
  --
  -- Additional rules
  -- - Ignore comment lines
  -- - Limit the logical line parsing to a certain number of lines ahead
  --   (Parsing is triggered by user edits, so without this limit, adding a quote would re-parse all lines.)
  local fields = {} ---@type CsvView.Parser.FieldInfo[]
  local terminated = true
  local current_lnum = lnum

  -- Get initial line
  local line = self._source.get_line(lnum)
  if not line then
    return false, fields, current_lnum, terminated
  end

  -- Check if the line is a comment line
  if self:_is_comment_line(line) then
    return true, fields, current_lnum, terminated
  end

  local line_count = self._source.get_line_count()

  local pos = 1
  local delimiter_match_count = 0
  local field_start = { lnum = lnum, pos = 1 }
  local multiline_field_parts = {} ---@type string[]

  --- Skip until the closing quote is found.
  --- This function advances `pos` until the closing quote is found.
  --- If the closing quote is not found within the lookahead limit, it returns false.
  ---@return boolean closed
  local function skip_until_closing_quote()
    while true do
      local found
      found, pos = self:_find_closing_quote_within_line(line, pos)
      if found then
        return true
      end

      if current_lnum >= math.min(lnum + self._max_lookahead, line_count) then
        -- Reached the lookahead limit without finding the closing quote
        terminated = false
        return false
      end

      -- Add the current line to the field text and continue to the next line
      local part = current_lnum == field_start.lnum and line:sub(field_start.pos) or line
      table.insert(multiline_field_parts, part)

      -- Look for the next line
      current_lnum = current_lnum + 1
      pos = 1
      line = self._source.get_line(current_lnum)
      if not line then
        -- Reached the end of the buffer
        return false
      end
    end
  end

  --- Add a field to the list of fields.
  ---@param end_pos integer
  local function add_field(end_pos)
    local is_field_multiline = current_lnum > field_start.lnum
    if is_field_multiline then
      local text = line:sub(1, end_pos)
      table.insert(multiline_field_parts, text)
      table.insert(fields, { start_pos = field_start.pos, text = multiline_field_parts })
      multiline_field_parts = {}
    else
      local text = line:sub(field_start.pos, end_pos)
      table.insert(fields, { start_pos = field_start.pos, text = text })
    end
  end

  -- Process the current line and potentially look ahead for multi-line fields
  while pos <= #line do
    local char = line:byte(pos)
    if char == self._quote_char then
      pos = pos + 1
      local closed = skip_until_closing_quote()
      if not closed then
        -- Could not find the closing quote within the lookahead limit
        -- Treat the rest of the line as a single field
        break
      end
    else
      local delimiter_match_state = self._delimiter.match(line, pos, char, delimiter_match_count)
      if delimiter_match_state == MatchState.MATCHING then
        -- A delimiter match is in progress
        delimiter_match_count = delimiter_match_count + 1
      elseif delimiter_match_state == MatchState.MATCH_COMPLETE then
        -- A complete delimiter match is found
        add_field(pos - (delimiter_match_count + 1))
        field_start.lnum = current_lnum
        field_start.pos = pos + 1
        delimiter_match_count = 0
      else
        -- No match, reset the delimiter match count
        delimiter_match_count = 0
      end
    end

    pos = pos + 1
  end

  -- Add the last field to the list
  if pos > 1 or field_start.lnum ~= current_lnum then
    add_field(pos - 1)
  end

  return false, fields, current_lnum, terminated
end

--- Parse CSV lines.
---@param async_chunksize integer The number of lines to parse in each async step.
---@param cb Csvview.Parser.Callbacks
---@param startlnum? integer 1-indexed start line number.
---@param endlnum? integer 1-indexed end line number.
---@param cancel_token? { cancelled:boolean }
function CsvViewParser:parse_lines(async_chunksize, cb, startlnum, endlnum, cancel_token)
  startlnum = startlnum or 1
  endlnum = endlnum or self._source.get_line_count()

  local iter_num = (endlnum - startlnum) / async_chunksize
  local on_success = cb.on_end
  local should_notify = iter_num > 1000
  if should_notify then
    local start_time = vim.uv.now()
    vim.notify("csvview: parsing buffer, please wait...")
    on_success = function()
      cb.on_end()
      local elapsed = vim.loop.now() - start_time
      vim.notify(string.format("csvview: parsing buffer done in %d[ms]", elapsed))
    end
  end

  local iter --- @type fun():nil
  local function do_step()
    local ok, err = xpcall(iter, util.wrap_stacktrace)
    if not ok then
      cb.on_end(util.format_error(err))
    end
  end

  local current_lnum = startlnum
  iter = function()
    if cancel_token and cancel_token.cancelled then
      cb.on_end("cancelled")
      return
    end

    local chunk_end = math.min(current_lnum + async_chunksize - 1, endlnum)
    while current_lnum <= chunk_end do
      local is_comment, fields, parse_endlnum, closed = self:parse_line(current_lnum)
      local new_endlnum = cb.on_line(current_lnum, is_comment, fields, parse_endlnum, closed)
      current_lnum = parse_endlnum + 1
      if new_endlnum then
        endlnum = new_endlnum
      end
    end

    if current_lnum <= endlnum then
      vim.schedule(do_step)
    else
      on_success()
    end
  end

  -- start parsing
  do_step()
end

--- Find the closing quote for a quoted field.
---@param line string The line to search in. mutate
---@param pos integer The starting position to search from.
---@return boolean found Whether the closing quote was found.
---@return integer pos The position of the closing quote.
function CsvViewParser:_find_closing_quote_within_line(line, pos)
  local len = #line
  while pos <= len do
    if line:byte(pos) == self._quote_char then
      if line:byte(pos + 1) == self._quote_char then
        -- This is an escaped quote, skip the next character
        pos = pos + 1
      else
        -- This is the end of the quoted field
        return true, pos
      end
    end

    pos = pos + 1
  end

  return false, pos
end

return CsvViewParser
