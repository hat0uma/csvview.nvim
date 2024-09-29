local M = {}

local DQUOTE = string.byte('"')
local SQUOTE = string.byte("'")

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

--- Get delimiter character
---@param bufnr integer
---@param opts CsvViewOptions
---@return integer
local function delim_byte(bufnr, opts)
  local delim = opts.parser.delimiter
  ---@diagnostic disable-next-line: no-unknown
  local char
  if type(delim) == "function" then
    char = delim(bufnr)
  end

  if type(delim) == "table" then
    char = delim[vim.bo.filetype] or delim.default
  end

  if type(delim) == "string" then
    char = delim
  end

  assert(type(char) == "string", string.format("delimiter must be a string, got %s", type(char)))
  assert(#char == 1, string.format("delimiter must be a single character, got %s", char))
  return char:byte()
end

--- parse line
---@param line string
---@param delim integer
---@return string[]
function M._parse_line(line, delim)
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
    elseif char == DQUOTE or char == SQUOTE then
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

--- get fields of line
---@param bufnr integer
---@param lnum integer
---@param delim integer
---@return string[]
function M.get_fields(bufnr, lnum, delim)
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, true)
  return M._parse_line(line[1], delim)
end

--- iterate fields async
---@param bufnr integer
---@param startlnum integer?
---@param endlnum integer?
---@param cb { on_line:fun( lnum:integer,columns:string[] ), on_end:fun() }
---@param opts CsvViewOptions
function M.iter_lines_async(bufnr, startlnum, endlnum, cb, opts)
  startlnum = startlnum or 1
  endlnum = endlnum or vim.api.nvim_buf_line_count(bufnr)

  local delim = delim_byte(bufnr, opts)
  local iter_num = (endlnum - startlnum) / opts.parser.async_chunksize
  local start_time = vim.uv.now()
  if iter_num > 500 then
    vim.notify("csvview: parsing buffer, please wait...")
  end

  -- Run in small chunks to avoid blocking the main thread
  local iter ---@type function
  iter = function()
    local chunkend = math.min(endlnum, startlnum + opts.parser.async_chunksize)
    for i = startlnum, chunkend do
      cb.on_line(i, M.get_fields(bufnr, i, delim))
    end

    -- next or end
    if chunkend < endlnum then
      startlnum = chunkend + 1
      vim.schedule(iter)
    else
      if iter_num > 500 then
        local elapsed = vim.uv.now() - start_time
        vim.notify(string.format("csvview: parsing buffer done in %d[ms]", elapsed))
      end
      cb.on_end()
    end
  end

  iter()
end

return M
