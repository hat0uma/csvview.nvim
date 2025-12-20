local util = require("csvview.util")

local str_byte = string.byte
local str_sub = string.sub

---@class CsvView.Parser.AsyncChunkOptions
---@field chunksize integer
---@field startlnum integer
---@field endlnum integer
---@field cancel_token? { cancelled: boolean }
---@field on_end fun(err: string?)

--- Run async chunked processing
---@param opts CsvView.Parser.AsyncChunkOptions
---@param process_chunk fun(chunk_start: integer, chunk_end: integer): integer, integer?
---   Returns: next_lnum, new_endlnum?
local function run_async_chunked(opts, process_chunk)
  local current_lnum = opts.startlnum
  local endlnum = opts.endlnum

  -- Notification wrapper for long operations
  local iter_num = (endlnum - opts.startlnum) / opts.chunksize
  local on_success = opts.on_end
  if iter_num > 1000 then
    local start_time = vim.uv.now()
    vim.notify("csvview: parsing buffer, please wait...")
    on_success = function()
      opts.on_end()
      local elapsed = vim.uv.now() - start_time
      vim.notify(string.format("csvview: parsing buffer done in %d[ms]", elapsed))
    end
  end

  local iter ---@type fun()
  local function do_step()
    local ok, err = xpcall(iter, util.wrap_stacktrace)
    if not ok then
      opts.on_end(util.format_error(err))
    end
  end

  iter = function()
    if opts.cancel_token and opts.cancel_token.cancelled then
      opts.on_end("cancelled")
      return
    end

    local chunk_end = math.min(current_lnum + opts.chunksize - 1, endlnum)
    local next_lnum, new_endlnum = process_chunk(current_lnum, chunk_end)
    current_lnum = next_lnum
    if new_endlnum then
      endlnum = new_endlnum
    end

    if current_lnum <= endlnum then
      vim.schedule(do_step)
    else
      on_success()
    end
  end

  do_step()
end

--- @class CsvView.Parser.Source
--- @field get_line fun(lnum:integer):string?
--- @field get_line_count fun():integer
--- @field invalidate? fun()

--- New buffer source
---@param bufnr integer
---@param chunk_size integer
---@return CsvView.Parser.Source
local function new_buffer_source(bufnr, chunk_size)
  local cache = nil --- @type string[]?
  local cache_start = 0 --- @type integer
  local cache_end = -1 --- @type integer
  local total_lines = nil --- @type integer?

  --- Get line
  ---@param lnum integer
  ---@return string
  local function get_line(lnum)
    -- Check if line is in current cache
    if cache and lnum >= cache_start and lnum <= cache_end then
      return cache[lnum - cache_start + 1]
    end

    -- Ensure total_lines is initialized
    if not total_lines then
      total_lines = vim.api.nvim_buf_line_count(bufnr)
    end

    -- Cache miss: Fetch next chunk (e.g., 100 lines)
    local start_row = lnum - 1
    local end_row = math.min(start_row + chunk_size, total_lines)

    cache = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row, true)
    cache_start = lnum
    cache_end = lnum + #cache - 1

    return cache[1]
  end

  local function get_line_count()
    if total_lines then
      return total_lines
    end

    total_lines = vim.api.nvim_buf_line_count(bufnr)
    return total_lines
  end

  local function invalidate()
    cache = nil
    cache_start = 0
    cache_end = -1
    total_lines = nil
  end

  return { --- @type CsvView.Parser.Source
    get_line_count = get_line_count,
    get_line = get_line,
    invalidate = invalidate,
  }
end

---@class CsvView.Parser.FieldInfo
---@field start_pos integer 1-based start position of the fields
---@field text string|string[] the text of the field. if the field is a quoted field, it will be a string array.

---@class CsvView.Parser.Events
---@field comment fun(lnum: integer)
---@field record_start fun(startlnum: integer)
---@field record_end fun(startlnum: integer, endlnum: integer, terminated: boolean)
---@field field fun(col_idx: integer, lnum: integer, line: string, offset: integer, endpos: integer)

---@class CsvView.Parser
---@field private _quote_char integer
---@field private _delim_bytes integer[]
---@field private _delim_str string
---@field private _is_comment_line fun(lnum:integer, line:string): boolean
---@field private _max_lookahead integer
---@field private _source CsvView.Parser.Source
local CsvViewParser = {}
CsvViewParser.__index = CsvViewParser

--- Create a new CsvView.Parser.
---@param bufnr integer Buffer number.
---@param opts CsvView.InternalOptions Options for parsing.
---@param quote_char string Quote character
---@param delimiter string Delimiter string.
---@return CsvView.Parser
function CsvViewParser:new(bufnr, opts, quote_char, delimiter)
  return CsvViewParser:new_with_source(
    quote_char:byte(),
    delimiter,
    util.create_is_comment(opts),
    opts.parser.max_lookahead,
    new_buffer_source(bufnr, 1000)
  )
end

--- Create a new CsvView.Parser from lines.
---@param quote_char integer Quote character byte.
---@param delimiter string Delimiter string.
---@param is_comment fun(lnum:integer, line:string): boolean
---@param max_lookahead integer Maximum number of lines to look ahead for multi-line fields.
---@param source CsvView.Parser.Source Source for getting lines.
---@return CsvView.Parser
function CsvViewParser:new_with_source(quote_char, delimiter, is_comment, max_lookahead, source)
  local obj = setmetatable({}, self)
  obj._quote_char = quote_char
  obj._delim_bytes = { delimiter:byte(1, #delimiter) }
  obj._delim_str = delimiter
  obj._is_comment_line = is_comment
  obj._max_lookahead = max_lookahead
  obj._source = source
  return obj
end

function CsvViewParser:invalidate_cache()
  if self._source.invalidate then
    self._source.invalidate()
  end
end

--- Returns an iterator that yields parsing events for the record starting at `lnum`.
---@param lnum integer
---@param events CsvView.Parser.Events
function CsvViewParser:parse_record(lnum, events)
  local line = self._source.get_line(lnum)
  if not line then
    return
  end

  -- Comment Check
  if self._is_comment_line(lnum, line) then
    events.comment(lnum)
    return
  end

  events.record_start(lnum)
  if #line == 0 then
    events.record_end(lnum, lnum, true)
    return
  end

  local len = #line
  local pos = 1
  local field_start = 1
  local col_idx = 1
  local current_lnum = lnum
  local terminated = true

  local delim_bytes = self._delim_bytes
  local delim_first_byte = delim_bytes[1]
  local max_lookahead = self._max_lookahead
  local delim_len = #self._delim_bytes
  local quote_char = self._quote_char
  local source = self._source

  while pos <= len do
    local b = str_byte(line, pos)

    if b == quote_char then
      -- QUOTED FIELD
      pos = pos + 1 -- Skip opening quote

      while true do
        local close_pos = self:_find_closing_quote(line, pos)
        if close_pos then
          -- Found closing quote on this line
          pos = close_pos + 1
          break
        end

        -- Multi-line field logic
        -- Grab rest of line
        events.field(col_idx, current_lnum, line, field_start - 1, #line)

        -- Check limits
        if current_lnum >= math.min(lnum + max_lookahead, source.get_line_count()) then
          terminated = false
          events.record_end(lnum, current_lnum, terminated)
          return
        end

        -- Fetch next line
        current_lnum = current_lnum + 1
        local next_line = source.get_line(current_lnum)
        if not next_line then -- EOF
          terminated = false
          events.record_end(lnum, current_lnum, terminated)
          return
        end
        -- Reset for new line
        line = next_line
        len = #line
        pos = 1
        field_start = 1
      end

    -- DELIMITER CHECK
    elseif b == delim_first_byte then
      local is_match = true
      if delim_len > 1 then
        -- Compare remaining bytes of multi-char delimiter
        for i = 2, delim_len do
          if str_byte(line, pos + i - 1) ~= delim_bytes[i] then
            is_match = false
            break
          end
        end
      end

      if is_match then
        -- Field Complete
        events.field(col_idx, current_lnum, line, field_start - 1, pos - 1)

        col_idx = col_idx + 1
        pos = pos + delim_len
        field_start = pos
      else
        pos = pos + 1
      end
    else
      -- Normal character, just advance
      pos = pos + 1
    end
  end

  -- Finalize last field
  events.field(col_idx, current_lnum, line, field_start - 1, len)
  events.record_end(lnum, current_lnum, terminated)
end

--- Create a field collector for convenience APIs.
--- NOTE: This collector extracts field text via string.sub, which has allocation overhead.
--- For performance-critical paths, use parse_records() with event callbacks directly.
local function create_field_collector()
  local fields = {} ---@type CsvView.Parser.FieldInfo[]
  local current_field = nil ---@type CsvView.Parser.FieldInfo?
  local current_col = 0
  local is_comment = false

  local events = {
    record_start = function() end,
    comment = function()
      is_comment = true
    end,
    field_newline = function() end,
    record_end = function()
      if current_field then
        table.insert(fields, current_field)
        current_field = nil
      end
    end,
    field = function(col_idx, _, line, offset, len)
      local text = str_sub(line, offset + 1, len)
      if col_idx ~= current_col then
        if current_field then
          table.insert(fields, current_field)
        end
        current_field = { start_pos = offset + 1, text = text }
        current_col = col_idx
      else
        -- Append to existing field (multiline)
        local t = current_field.text
        if type(t) == "table" then
          table.insert(t, text)
        else
          current_field.text = { t, text }
        end
      end
    end,
  }
  return events, function()
    return fields, is_comment
  end
end

--- Parse a single line and return field info table.
--- NOTE: This is a convenience API for testing and simple use cases.
--- For performance-critical paths, use parse_records() with event callbacks directly.
---@param lnum integer
---@return boolean is_comment
---@return CsvView.Parser.FieldInfo[] fields
---@return integer endlnum
---@return boolean terminated
function CsvViewParser:parse_line(lnum)
  local events, get_result = create_field_collector()
  local endlnum_result = lnum
  local terminated_result = true

  -- Hook into record_end to capture status
  local original_end = events.record_end
  events.record_end = function(_, endlnum, terminated)
    endlnum_result = endlnum
    terminated_result = terminated
    original_end()
  end

  self:parse_record(lnum, events)
  local fields, is_comment = get_result()
  return is_comment, fields, endlnum_result, terminated_result
end

---@class CsvView.Parser.RecordCallbacks
---@field on_comment fun(lnum: integer) called for comment lines
---@field on_record_start fun(lnum: integer) called when a record starts
---@field on_field fun(col_idx: integer, lnum: integer, line: string, offset: integer, endpos: integer) called for each field
---@field on_record_end fun(startlnum: integer, endlnum: integer, terminated: boolean): integer? called when a record ends. Returns new endlnum if needed.
---@field on_end fun(err: string?) called when parsing is complete

--- Parse records using event-based callbacks with async chunking
---@param async_chunksize integer
---@param cb CsvView.Parser.RecordCallbacks
---@param startlnum? integer
---@param endlnum? integer
---@param cancel_token? { cancelled: boolean }
function CsvViewParser:parse_records(async_chunksize, cb, startlnum, endlnum, cancel_token)
  startlnum = startlnum or 1
  endlnum = endlnum or self._source.get_line_count()

  local current_record_end = startlnum
  local endlnum_override = nil

  -- Create event callbacks
  local events = {
    comment = function(lnum)
      current_record_end = lnum
      cb.on_comment(lnum)
    end,
    record_start = function(lnum)
      cb.on_record_start(lnum)
    end,
    record_end = function(start_lnum, end_lnum, terminated)
      current_record_end = end_lnum
      endlnum_override = cb.on_record_end(start_lnum, end_lnum, terminated)
    end,
    field = cb.on_field,
  }

  run_async_chunked({
    chunksize = async_chunksize,
    startlnum = startlnum,
    endlnum = endlnum,
    cancel_token = cancel_token,
    on_end = cb.on_end,
  }, function(chunk_start, chunk_end)
    local lnum = chunk_start
    while lnum <= chunk_end do
      self:parse_record(lnum, events)
      lnum = current_record_end + 1
    end
    local new_end = endlnum_override
    endlnum_override = nil
    return lnum, new_end
  end)
end

--- Find the closing quote for a quoted field.
---@param line string The line to search in. mutate
---@param start_pos integer The starting position to search from.
---@return integer? pos The position of the closing quote.
function CsvViewParser:_find_closing_quote(line, start_pos)
  local len = #line
  local q = self._quote_char
  local pos = start_pos

  while pos <= len do
    if str_byte(line, pos) == q then
      if str_byte(line, pos + 1) == q then
        -- This is an escaped quote, skip the next character
        pos = pos + 1
      else
        -- This is the end of the quoted field
        return pos
      end
    end

    pos = pos + 1
  end

  return nil
end

return CsvViewParser
