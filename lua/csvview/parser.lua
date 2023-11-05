local M = {}

local DELIM = string.byte(",")

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

--- iterate fields async
---@param bufnr integer
---@param startlnum integer?
---@param endlnum integer?
---@param cb { on_line:fun( lnum:integer,columns:string[] ), on_end:fun() }
---@param opts CsvViewOptions
function M.iter_lines_async(bufnr, startlnum, endlnum, cb, opts)
  startlnum = startlnum or 1
  endlnum = endlnum or vim.api.nvim_buf_line_count(bufnr)
  local iter_num = (endlnum - startlnum) / opts.parser.async_chunksize
  if iter_num > 500 then
    print("csvview: parsing buffer, please wait...")
  end

  -- Run in small chunks to avoid blocking the main thread
  local iter ---@type function
  iter = function()
    local chunkend = math.min(endlnum, startlnum + opts.parser.async_chunksize)
    for i = startlnum, chunkend do
      cb.on_line(i, M.get_fields(bufnr, i))
    end

    -- next or end
    if chunkend < endlnum then
      startlnum = chunkend + 1
      vim.defer_fn(iter, 1)
    else
      if iter_num > 500 then
        print("csvview: parsing buffer done")
      end
      cb.on_end()
    end
  end

  iter()
end

return M
