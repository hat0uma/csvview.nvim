local util = require("csvview.util")

local str_byte = string.byte
local str_sub = string.sub

-- NOTE: Avoid creating closures per parse in the hot paths of this module.
-- LuaJIT specializes traces to the closure objects that are called (and folds their upvalues as constants).
-- If closures are recreated for every parse, the traces compiled in the first parse no longer match,
-- and every subsequent parse falls back to the interpreter. Use objects with methods instead.

---@class CsvView.Parser.AsyncChunkOptions
---@field chunksize integer
---@field startlnum integer
---@field endlnum integer
---@field cancel_token? { cancelled: boolean }
---@field on_end fun(err: string?)

--- Run async chunked processing
---@generic T
---@param opts CsvView.Parser.AsyncChunkOptions
---@param process_chunk fun(ctx: T, chunk_start: integer, chunk_end: integer): integer, integer?
---   Returns: next_lnum, new_endlnum?
---@param ctx T context passed to `process_chunk`
local function run_async_chunked(opts, process_chunk, ctx)
  local current_lnum = opts.startlnum
  local endlnum = opts.endlnum

  -- Notification wrapper for long operations
  local iter_num = (endlnum - opts.startlnum) / opts.chunksize
  local on_success = opts.on_end
  if iter_num > 1000 then
    local start_time = vim.uv.hrtime()
    vim.notify("csvview: parsing buffer, please wait...")
    on_success = function()
      opts.on_end()
      local elapsed = (vim.uv.hrtime() - start_time) / 1e6
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
    local next_lnum, new_endlnum = process_chunk(ctx, current_lnum, chunk_end)
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
--- @field get_line fun(self: CsvView.Parser.Source, lnum:integer):string?
--- @field get_line_count fun(self: CsvView.Parser.Source):integer
--- @field invalidate? fun(self: CsvView.Parser.Source)

--- Source that reads lines from a buffer in chunks
--- @class CsvView.Parser.BufferSource: CsvView.Parser.Source
--- @field private _bufnr integer
--- @field private _chunk_size integer
--- @field private _cache string[]?
--- @field private _cache_start integer
--- @field private _cache_end integer
--- @field private _total_lines integer?
local BufferSource = {}
BufferSource.__index = BufferSource

--- New buffer source
---@param bufnr integer
---@param chunk_size integer
---@return CsvView.Parser.BufferSource
function BufferSource:new(bufnr, chunk_size)
  local obj = setmetatable({}, self)
  obj._bufnr = bufnr
  obj._chunk_size = chunk_size
  obj._cache = nil
  obj._cache_start = 0
  obj._cache_end = -1
  obj._total_lines = nil
  return obj
end

--- Get line
---@param lnum integer
---@return string?
function BufferSource:get_line(lnum)
  -- Check if line is in current cache
  local cache = self._cache
  if cache and lnum >= self._cache_start and lnum <= self._cache_end then
    return cache[lnum - self._cache_start + 1]
  end

  -- Ensure total_lines is initialized
  local total_lines = self:get_line_count()

  -- Cache miss: Fetch next chunk (e.g., 100 lines)
  local start_row = lnum - 1
  local end_row = math.min(start_row + self._chunk_size, total_lines)

  cache = vim.api.nvim_buf_get_lines(self._bufnr, start_row, end_row, true)
  self._cache = cache
  self._cache_start = lnum
  self._cache_end = lnum + #cache - 1

  return cache[1]
end

---@return integer
function BufferSource:get_line_count()
  local total_lines = self._total_lines
  if total_lines then
    return total_lines
  end

  total_lines = vim.api.nvim_buf_line_count(self._bufnr)
  self._total_lines = total_lines
  return total_lines
end

function BufferSource:invalidate()
  self._cache = nil
  self._cache_start = 0
  self._cache_end = -1
  self._total_lines = nil
end

--- Source that reads lines from a list of lines
--- @class CsvView.Parser.LinesSource: CsvView.Parser.Source
--- @field private _lines string[]
local LinesSource = {}
LinesSource.__index = LinesSource

---@param lines string[]
---@return CsvView.Parser.LinesSource
function LinesSource:new(lines)
  return setmetatable({ _lines = lines }, self)
end

---@param lnum integer
---@return string?
function LinesSource:get_line(lnum)
  return self._lines[lnum]
end

---@return integer
function LinesSource:get_line_count()
  return #self._lines
end

---@class CsvView.Parser.FieldInfo
---@field start_pos integer 1-based start position of the fields
---@field text string|string[] the text of the field. if the field is a quoted field, it will be a string array.

--- Parsing event handler. Events are dispatched as method calls (`handler:on_field(...)`).
---@class CsvView.Parser.Handler
---@field on_comment fun(self: CsvView.Parser.Handler, lnum: integer) called for comment lines
---@field on_record_start fun(self: CsvView.Parser.Handler, lnum: integer) called when a record starts
---@field on_field fun(self: CsvView.Parser.Handler, col_idx: integer, lnum: integer, line: string, offset: integer, endpos: integer) called for each field
---@field on_record_end fun(self: CsvView.Parser.Handler, startlnum: integer, endlnum: integer, terminated: boolean): integer? called when a record ends. Returns new endlnum if needed.

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
    BufferSource:new(bufnr, 1000)
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
    self._source:invalidate()
  end
end

--- Parse the record starting at `lnum` and dispatch parsing events to `handler`.
---@param lnum integer
---@param handler CsvView.Parser.Handler
---@return integer endlnum the last line number of the record
---@return integer? new_endlnum the value returned by `handler:on_record_end`
function CsvViewParser:parse_record(lnum, handler)
  local source = self._source
  local line = source:get_line(lnum)
  if not line then
    return lnum
  end

  -- Comment Check
  if self._is_comment_line(lnum, line) then
    handler:on_comment(lnum)
    return lnum
  end

  handler:on_record_start(lnum)
  if #line == 0 then
    return lnum, handler:on_record_end(lnum, lnum, true)
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
        handler:on_field(col_idx, current_lnum, line, field_start - 1, #line)

        -- Check limits
        if current_lnum >= math.min(lnum + max_lookahead, source:get_line_count()) then
          terminated = false
          return current_lnum, handler:on_record_end(lnum, current_lnum, terminated)
        end

        -- Fetch next line
        current_lnum = current_lnum + 1
        local next_line = source:get_line(current_lnum)
        if not next_line then -- EOF
          terminated = false
          return current_lnum, handler:on_record_end(lnum, current_lnum, terminated)
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
        handler:on_field(col_idx, current_lnum, line, field_start - 1, pos - 1)

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
  handler:on_field(col_idx, current_lnum, line, field_start - 1, len)
  return current_lnum, handler:on_record_end(lnum, current_lnum, terminated)
end

--- Field collector for convenience APIs.
--- NOTE: This collector extracts field text via string.sub, which has allocation overhead.
--- For performance-critical paths, use parse_records() with a handler directly.
---@class CsvView.Parser.FieldCollector: CsvView.Parser.Handler
---@field fields CsvView.Parser.FieldInfo[]
---@field is_comment boolean
---@field terminated boolean
---@field private _current_field CsvView.Parser.FieldInfo?
---@field private _current_col integer
local FieldCollector = {}
FieldCollector.__index = FieldCollector

---@return CsvView.Parser.FieldCollector
function FieldCollector:new()
  local obj = setmetatable({}, self)
  obj.fields = {}
  obj.is_comment = false
  obj.terminated = true
  obj._current_field = nil
  obj._current_col = 0
  return obj
end

function FieldCollector:on_comment()
  self.is_comment = true
end

function FieldCollector:on_record_start() end

function FieldCollector:on_record_end(_, _, terminated)
  self.terminated = terminated
  if self._current_field then
    table.insert(self.fields, self._current_field)
    self._current_field = nil
  end
end

function FieldCollector:on_field(col_idx, _, line, offset, len)
  local text = str_sub(line, offset + 1, len)
  if col_idx ~= self._current_col then
    if self._current_field then
      table.insert(self.fields, self._current_field)
    end
    self._current_field = { start_pos = offset + 1, text = text }
    self._current_col = col_idx
  else
    -- Append to existing field (multiline)
    local t = self._current_field.text
    if type(t) == "table" then
      table.insert(t, text)
    else
      self._current_field.text = { t, text }
    end
  end
end

--- Parse a single line and return field info table.
--- NOTE: This is a convenience API for testing and simple use cases.
--- For performance-critical paths, use parse_records() with a handler directly.
---@param lnum integer
---@return boolean is_comment
---@return CsvView.Parser.FieldInfo[] fields
---@return integer endlnum
---@return boolean terminated
function CsvViewParser:parse_line(lnum)
  local collector = FieldCollector:new()
  local endlnum = self:parse_record(lnum, collector)
  return collector.is_comment, collector.fields, endlnum, collector.terminated
end

---@class CsvView.Parser.RecordsHandler: CsvView.Parser.Handler
---@field on_end fun(self: CsvView.Parser.RecordsHandler, err: string?) called when parsing is complete

---@class CsvView.Parser.ChunkContext
---@field parser CsvView.Parser
---@field handler CsvView.Parser.RecordsHandler

--- Parse the records in a chunk
---@param ctx CsvView.Parser.ChunkContext
---@param chunk_start integer
---@param chunk_end integer
---@return integer next_lnum
---@return integer? new_endlnum
local function parse_chunk(ctx, chunk_start, chunk_end)
  local parser = ctx.parser
  local handler = ctx.handler
  local lnum = chunk_start
  local new_endlnum = nil ---@type integer?
  while lnum <= chunk_end do
    local record_end, endlnum_override = parser:parse_record(lnum, handler)
    if endlnum_override then
      new_endlnum = endlnum_override
    end
    lnum = record_end + 1
  end
  return lnum, new_endlnum
end

--- Parse records with async chunking, dispatching parsing events to `handler`.
---@param async_chunksize integer
---@param handler CsvView.Parser.RecordsHandler
---@param startlnum? integer
---@param endlnum? integer
---@param cancel_token? { cancelled: boolean }
function CsvViewParser:parse_records(async_chunksize, handler, startlnum, endlnum, cancel_token)
  startlnum = startlnum or 1
  endlnum = endlnum or self._source:get_line_count()

  run_async_chunked({
    chunksize = async_chunksize,
    startlnum = startlnum,
    endlnum = endlnum,
    cancel_token = cancel_token,
    on_end = function(err)
      handler:on_end(err)
    end,
  }, parse_chunk, { parser = self, handler = handler })
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

CsvViewParser.BufferSource = BufferSource
CsvViewParser.LinesSource = LinesSource

return CsvViewParser
