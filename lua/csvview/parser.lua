local M = {}
local errors = require("csvview.errors")

---@class Csvview.Parser.Callbacks
---@field on_line fun(lnum:integer,is_comment:boolean,fields:string[]) the callback to be called for each line
---@field on_end fun() the callback to be called when parsing is done

--- Find the next character in a string.
---@param s string
---@param start_pos integer start position
---@param char integer byte value of character to find
---@return integer?
local function find_char(s, start_pos, char)
  local len = #s
  for i = start_pos, len do
    if string.byte(s, i) == char then
      return i
    end
  end
  return nil
end

--- Check if line is a comment
---@param line string
---@param opts CsvView.Options
---@return boolean
local function is_comment_line(line, opts)
  for _, comment in ipairs(opts.parser.comments) do
    if vim.startswith(line, comment) then
      return true
    end
  end
  return false
end

--- Get delimiter character
---@param bufnr integer
---@param opts CsvView.Options
---@return integer
local function delim_byte(bufnr, opts)
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

  assert(type(char) == "string", string.format("delimiter must be a string, got %s", type(char)))
  assert(#char == 1, string.format("delimiter must be a single character, got %s", char))
  return char:byte()
end

--- Get quote char character
---@param bufnr integer
---@param opts CsvView.Options
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

--- parse line
---@param line string
---@param delim integer
---@param quote_char integer
---@return string[]
function M._parse_line(line, delim, quote_char)
  local len = #line
  if len == 0 then
    return {}
  end

  local fields = {} --- @type string[]
  local field_start_pos = 1
  local pos = 1

  while pos <= len do
    local char = string.byte(line, pos)
    if char == delim then
      -- add field (even if empty).
      fields[#fields + 1] = string.sub(line, field_start_pos, pos - 1)
      field_start_pos = pos + 1
    elseif char == quote_char then
      -- find closing quote and skip it.
      -- if there is no closing quote, skip the rest of the line.
      local close_pos = find_char(line, pos + 1, char)
      if close_pos then
        pos = close_pos
      else
        pos = len
      end
    end
    pos = pos + 1
  end

  -- add last field (even if empty).
  fields[#fields + 1] = string.sub(line, field_start_pos, pos - 1)
  return fields
end

---@async
--- iterate fields
---@param startlnum integer  1-indexed start line number
---@param endlnum integer  1-indexed end line number
---@param bufnr integer
---@param opts CsvView.Options
---@param cb Csvview.Parser.Callbacks
local function iter(startlnum, endlnum, bufnr, opts, cb)
  local iter_num = (endlnum - startlnum) / opts.parser.async_chunksize
  local should_notify = iter_num > 1000
  local start_time = vim.uv.now()
  if should_notify then
    vim.notify("csvview: parsing buffer, please wait...")
  end

  local delim = delim_byte(bufnr, opts)
  local quote_char = quote_char_byte(bufnr, opts)

  local function parse_line(lnum) ---@param lnum integer
    local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, true)[1]
    if is_comment_line(line, opts) then
      cb.on_line(lnum, true, {})
    else
      local fields = M._parse_line(line, delim, quote_char)
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
---@param opts CsvView.Options
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
