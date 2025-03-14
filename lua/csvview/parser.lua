local M = {}
local config = require("csvview.config")
local errors = require("csvview.errors")

---@class Csvview.Parser.Callbacks
---@field on_line fun(lnum:integer,is_comment:boolean,fields:string[]) the callback to be called for each line
---@field on_end fun() the callback to be called when parsing is done

---@enum ParseState
local PARSE_STATES = {
  --- Parsing characters within a field.
  IN_FIELD = 1,
  --- Parsing characters within a quoted field.
  IN_QUOTED_FIELD = 2,
  --- Checking if the current sequence of characters matches the delimiter.
  MATCHING_DELIMITER = 3,
}

---@class CsvView.Parser.DelimiterPolicy
---@field match fun(s:string, pos:integer, char:integer, match_count:integer): boolean
---@field check_match_complete fun(s:string, pos:integer, char:integer, match_count:integer): boolean

--- Create a delimiter policy.
---@param opts CsvView.InternalOptions
---@param bufnr integer
---@return CsvView.Parser.DelimiterPolicy
function M._create_delimiter_policy(opts, bufnr)
  local delim = config.resolve_delimiter(opts, bufnr)
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

--- Check if line is a comment
---@param line string
---@param opts CsvView.InternalOptions
---@return boolean
local function is_comment_line(line, opts)
  for _, comment in ipairs(opts.parser.comments) do
    if vim.startswith(line, comment) then
      return true
    end
  end
  return false
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

--- Parse a CSV line.
---@param line string
---@param delimiter CsvView.Parser.DelimiterPolicy delimiter policy.
---@param quote_char integer byte code of the quote character.
---@return string[]
function M._parse_line(line, delimiter, quote_char)
  local fields = {} ---@type string[]

  local len = #line
  local state = PARSE_STATES.IN_FIELD
  local delimiter_match_count = 0
  local field_start_pos = 1
  local pos = 1

  if len == 0 then
    return fields
  end

  -- DFA-based parser that handles quoted fields and delimiter characters.
  --
  -- The parser transitions between three states:
  --   **IN_FIELD**: Checks for the start of a delimiter or a quote.
  --   **IN_QUOTED_FIELD**: Looks for the closing quote to return to `IN_FIELD`.
  --   **MATCHING_DELIMITER**: Continues matching the delimiter or transitions to `IN_QUOTED_FIELD` if a quote is found.
  -- The exact implementation should consider escaping quotes, but it is omitted because it is irrelevant to the display.
  while pos <= len do
    local char = line:byte(pos)
    if state == PARSE_STATES.IN_FIELD then
      if delimiter.match(line, pos, char, 0) then
        delimiter_match_count = 1
        state = PARSE_STATES.MATCHING_DELIMITER
      elseif char == quote_char then
        state = PARSE_STATES.IN_QUOTED_FIELD
      end
    elseif state == PARSE_STATES.IN_QUOTED_FIELD then
      if char == quote_char then
        state = PARSE_STATES.IN_FIELD
      end
    elseif state == PARSE_STATES.MATCHING_DELIMITER then
      if delimiter.match(line, pos, char, delimiter_match_count) then
        delimiter_match_count = delimiter_match_count + 1
      elseif char == quote_char then
        delimiter_match_count = 0
        state = PARSE_STATES.IN_QUOTED_FIELD
      else
        delimiter_match_count = 0
        state = PARSE_STATES.IN_FIELD
      end
    end

    -- If the delimiter is fully matched, add the field to the list and reset the state.
    if
      state == PARSE_STATES.MATCHING_DELIMITER
      and delimiter.check_match_complete(line, pos, char, delimiter_match_count)
    then
      fields[#fields + 1] = line:sub(field_start_pos, pos - delimiter_match_count)
      field_start_pos = pos + 1
      delimiter_match_count = 0
      state = PARSE_STATES.IN_FIELD
    end

    pos = pos + 1
  end

  -- -- Add the last field to the list.
  fields[#fields + 1] = line:sub(field_start_pos, pos - 1)
  return fields
end

---@async
--- iterate fields
---@param startlnum integer  1-indexed start line number
---@param endlnum integer  1-indexed end line number
---@param bufnr integer
---@param opts CsvView.InternalOptions
---@param cb Csvview.Parser.Callbacks
local function iter(startlnum, endlnum, bufnr, opts, cb)
  local iter_num = (endlnum - startlnum) / opts.parser.async_chunksize
  local should_notify = iter_num > 1000
  local start_time = vim.uv.now()
  if should_notify then
    vim.notify("csvview: parsing buffer, please wait...")
  end

  local quote_char = quote_char_byte(bufnr, opts)
  local delimiter = M._create_delimiter_policy(opts, bufnr)

  local function parse_line(lnum) ---@param lnum integer
    local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, true)[1]
    if is_comment_line(line, opts) then
      cb.on_line(lnum, true, {})
    else
      local fields = M._parse_line(line, delimiter, quote_char)
      cb.on_line(lnum, false, fields)
    end
  end

  -- iterate lines
  local parsed_num = 0
  for i = startlnum, endlnum do
    local ok, err = xpcall(parse_line, errors.wrap_stacktrace, i)
    if not ok then
      errors.error_with_context(err, { lnum = i })
    end

    -- yield every chunksize
    parsed_num = parsed_num + 1
    if parsed_num >= opts.parser.async_chunksize then
      parsed_num = 0
      coroutine.yield()
    end
  end

  -- notify end of parsing
  cb.on_end()
  if should_notify then
    local elapsed = vim.loop.now() - start_time
    vim.notify(string.format("csvview: parsing buffer done in %d[ms]", elapsed))
  end
end

--- iterate fields async
---@param bufnr integer
---@param startlnum integer?
---@param endlnum integer?
---@param cb Csvview.Parser.Callbacks
---@param opts CsvView.InternalOptions
function M.iter_lines_async(bufnr, startlnum, endlnum, cb, opts)
  startlnum = startlnum or 1
  endlnum = endlnum or vim.api.nvim_buf_line_count(bufnr)

  -- create coroutine to iterate lines
  local co = coroutine.create(function() ---@async
    local ok, err = xpcall(iter, errors.wrap_stacktrace, startlnum, endlnum, bufnr, opts, cb)
    if not ok then
      errors.error_with_context(err, { startlnum = startlnum, endlnum = endlnum })
    end
  end)

  local function resume_co()
    local ok, err = coroutine.resume(co)
    if not ok then
      errors.print_structured_error("CsvView Error parsing buffer", err)
    elseif coroutine.status(co) ~= "dead" then
      vim.schedule(resume_co)
    end
  end

  -- start coroutine
  resume_co()
end

return M
