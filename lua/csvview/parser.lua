local errors = require("csvview.errors")

---@class CsvView.Parser.FieldInfo
---@field start_pos integer 1-based start position of the fields
---@field text string|string[] the text of the field. if the field is a quoted field, it will be a string array.

---@class Csvview.Parser.Callbacks
---@field on_line fun(lnum:integer,is_comment:boolean,fields:CsvView.Parser.FieldInfo[]) the callback to be called for each line.
---@field on_end fun(err?:string) the callback to be called when parsing is done

---@class CsvView.Parser.DelimiterPolicy
---@field match fun(s:string, pos:integer, char:integer, match_count:integer): boolean
---@field check_match_complete fun(s:string, pos:integer, char:integer, match_count:integer): boolean

--- Resolve delimiter character
---@param opts CsvView.InternalOptions
---@param bufnr integer
---@return string
local function resolve_delimiter(opts, bufnr)
  local delim = opts.parser.delimiter
  ---@diagnostic disable-next-line: no-unknown
  local char
  if type(delim) == "function" then
    char = delim(bufnr)
  end

  if type(delim) == "table" then
    char = delim.ft[vim.bo.filetype] or delim.default
  end

  if type(delim) == "string" then
    char = delim
  end

  assert(type(char) == "string", string.format("unknown delimiter type: %s", type(char)))
  return char
end

--- Create a delimiter policy.
---@param opts CsvView.InternalOptions
---@param bufnr integer
---@return CsvView.Parser.DelimiterPolicy
local function create_delimiter_policy(opts, bufnr)
  local delim = resolve_delimiter(opts, bufnr)
  local delim_len = #delim
  local delim_bytes = { string.byte(delim, 1, delim_len) }
  return { ---@type CsvView.Parser.DelimiterPolicy
    match = function(s, pos, char, match_count)
      return char == delim_bytes[match_count + 1]
    end,
    check_match_complete = function(s, pos, char, match_count)
      return match_count == delim_len
    end,
  }
end

--- Get quote char character
---@param bufnr integer
---@param opts CsvView.InternalOptions
---@return integer
local function quote_char_byte(bufnr, opts)
  local delim = opts.parser.quote_char
  ---@diagnostic disable-next-line: no-unknown
  local char
  if type(delim) == "string" then
    char = delim
  end

  assert(type(char) == "string", string.format("quote char must be a string, got %s", type(char)))
  assert(#char == 1, string.format("quote char must be a single character, got %s", char))
  return char:byte()
end

---@class CsvView.Parser
---@field private _bufnr integer Buffer number.
---@field private _opts CsvView.InternalOptions Options for parsing.
---@field private _quote_char integer Quote character byte.
---@field private _delimiter CsvView.Parser.DelimiterPolicy Delimiter policy.
---@field _max_lookahead integer Maximum lookahead for multi-line fields.
local CsvViewParser = {}

--- Create a new CsvView.Parser.
---@param bufnr integer Buffer number.
---@param opts CsvView.InternalOptions Options for parsing.
---@return CsvView.Parser
function CsvViewParser:new(bufnr, opts)
  local obj = {}
  obj._bufnr = bufnr
  obj._opts = opts
  obj._quote_char = quote_char_byte(bufnr, opts)
  obj._delimiter = create_delimiter_policy(opts, bufnr)
  obj._max_lookahead = 0

  setmetatable(obj, self)
  self.__index = self
  return obj
end

--- Get line
---@param lnum integer 1-indexed line number.
---@return string line The line text.
function CsvViewParser:_get_line(lnum)
  return vim.api.nvim_buf_get_lines(self._bufnr, lnum - 1, lnum, true)[1]
end

--- Check if line is a comment
---@param line string
---@return boolean
function CsvViewParser:_is_comment_line(line)
  for _, comment in ipairs(self._opts.parser.comments) do
    if vim.startswith(line, comment) then
      return true
    end
  end
  return false
end

--- Parse CSV lines.
---@param lnum integer 1-indexed line number.
---@return boolean is_comment_line Whether the line is a comment line.
---@return CsvView.Parser.FieldInfo[] fields An array of field information.
---@return integer endlnum The end line number.
function CsvViewParser:_parse_line(lnum)
  -- Assume CSV format compliant with RFC 4180
  -- - Each record is separated by a newline or delimiter.
  -- - If a field contains commas or newlines, enclose it in quote characters.
  -- - If a field contains quote characters, escape them by doubling the quote characters.
  --
  -- Additional rules
  -- - Ignore comment lines
  -- - Limit the search for closing quotes to a specified number of lines.
  --   (Parsing is triggered by user edits, so without this limit, adding a quote would re-parse all lines.)
  local fields = {} ---@type CsvView.Parser.FieldInfo[]
  local start_lnum = lnum
  local current_lnum = lnum

  -- Get initial line
  local line = self:_get_line(lnum)
  if not line then
    return false, fields, current_lnum
  end

  -- Check if the line is a comment line
  if self:_is_comment_line(line) then
    return true, fields, current_lnum
  end

  local pos = 1
  local delimiter_match_count = 0
  local field_start = { lnum = lnum, pos = 1 }
  local multiline_field_parts = {} ---@type string[]

  --- Skip until the closing quote is found.
  ---@return boolean closed
  local function skip_until_closing_quote()
    while true do
      local char = line:byte(pos)
      if not char then
        -- We're in a quoted field that spans multiple lines
        if current_lnum >= (start_lnum + self._max_lookahead) then
          -- We've reached the maximum lookahead, treat this as the end of the field
          break
        end

        -- Add the current line to the field text and continue to the next line
        if field_start.lnum == current_lnum then
          -- If we're still on the same line, just append the text
          table.insert(multiline_field_parts, line:sub(field_start.pos))
        else
          table.insert(multiline_field_parts, line)
        end

        current_lnum = current_lnum + 1
        line = self:_get_line(current_lnum)
        if not line then
          -- End of buffer reached while in a quoted field
          break
        end

        pos = 1
        char = line:byte(pos)
      end

      if char == self._quote_char then
        local next_char = line:byte(pos + 1)
        if next_char == self._quote_char then
          -- This is an escaped quote, skip the next character
          pos = pos + 1
        else
          -- This is the end of the quoted field
          return true
        end
      end

      pos = pos + 1
    end

    return false
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
        -- If we reach here, it means we didn't find a closing quote
        -- We break out of the loop and treat this as the end of the field
        break
      end
    elseif self._delimiter.match(line, pos, char, delimiter_match_count) then
      delimiter_match_count = delimiter_match_count + 1
      if self._delimiter.check_match_complete(line, pos, char, delimiter_match_count) then
        -- If the delimiter is fully matched, add the field to the list and reset the state
        add_field(pos - delimiter_match_count)
        field_start.lnum = current_lnum
        field_start.pos = pos + 1
        delimiter_match_count = 0
      end
    else
      delimiter_match_count = 0
    end

    pos = pos + 1
  end

  -- Add the last field to the list
  if pos > 1 then
    add_field(pos - 1)
  end

  return false, fields, current_lnum
end

--- Parse CSV lines.
---@param cb Csvview.Parser.Callbacks
---@param startlnum? integer 1-indexed start line number.
---@param endlnum? integer 1-indexed end line number.
function CsvViewParser:parse_lines(cb, startlnum, endlnum)
  startlnum = startlnum or 1
  endlnum = endlnum or vim.api.nvim_buf_line_count(self._bufnr)

  local iter_num = (endlnum - startlnum) / self._opts.parser.async_chunksize
  local should_notify = iter_num > 1000
  local start_time = vim.uv.now()
  if should_notify then
    vim.notify("csvview: parsing buffer, please wait...")
  end

  local iter --- @type fun():nil
  local function do_step()
    local ok, err = xpcall(iter, errors.wrap_stacktrace)
    if not ok then
      cb.on_end(errors.format_error(err))
    end
  end

  local current_lnum = startlnum
  iter = function()
    local chunk_end = math.min(current_lnum + self._opts.parser.async_chunksize - 1, endlnum)
    while current_lnum <= chunk_end do
      local is_comment, fields
      is_comment, fields, current_lnum = self:_parse_line(current_lnum)
      cb.on_line(current_lnum, is_comment, fields)
      current_lnum = current_lnum + 1
    end

    if current_lnum < endlnum then
      vim.schedule(do_step)
    else
      cb.on_end()
      if should_notify then
        local elapsed = vim.loop.now() - start_time
        vim.notify(string.format("csvview: parsing buffer done in %d[ms]", elapsed))
      end
    end
  end

  -- start parsing
  do_step()
end

return CsvViewParser
