local M = {}

local DELIM = string.byte(",")

local config = {
  async_chunksize = 50,
}

--- parse line
---@param line string
---@return string[]
function M._parse_line(line)
  local len = #line
  if len == 0 then
    return {}
  end

  local fields = {} --- @type string[]
  local field_start_pos = 1
  local pos = 1
  while pos <= len do
    local char = string.byte(line, pos)
    if char == DELIM then
      fields[#fields + 1] = string.sub(line, field_start_pos, pos - 1)
      field_start_pos = pos + 1
    end
    pos = pos + 1
  end
  fields[#fields + 1] = string.sub(line, field_start_pos, pos - 1)
  return fields
end

--- get fields of line
---@param bufnr integer
---@param lnum integer
---@return string[]
function M.get_fields(bufnr, lnum)
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, true)
  return M._parse_line(line[1])
end

--- iterate fields
---@param bufnr integer
---@param startlnum integer?
---@param endlnum integer?
---@return fun():integer?,string[]?
function M.iter_lines(bufnr, startlnum, endlnum)
  local lnum = endlnum and endlnum or vim.api.nvim_buf_line_count(bufnr)
  local i = startlnum and startlnum - 1 or 0
  return function()
    if i >= lnum then
      return nil, nil
    end

    i = i + 1
    return i, M.get_fields(bufnr, i)
  end
end

--- iterate fields async
---@param bufnr integer
---@param startlnum integer?
---@param endlnum integer?
---@param on_line fun( lnum:integer,columns:string[] )
---@param on_end fun()
function M.iter_lines_async(bufnr, startlnum, endlnum, on_line, on_end)
  startlnum = startlnum or 1
  endlnum = endlnum or vim.api.nvim_buf_line_count(bufnr)

  -- Run in small chunks to avoid blocking the main thread
  local iter ---@type function
  iter = function()
    if startlnum >= endlnum then
      on_end()
      return
    end

    local batch = math.min(endlnum - startlnum, config.async_chunksize)
    for i = startlnum, startlnum + batch do
      on_line(i, M.get_fields(bufnr, i))
    end
    startlnum = startlnum + batch
    -- vim.schedule(iter)
    vim.defer_fn(iter, 1)
  end

  iter()
end

return M
