local parser = require("csvview.parser")
local M = {}

--- @class CsvFieldMetrics
--- @field len integer
--- @field display_width integer
--- @field is_number boolean

--- Get the maximum width of each column
---@param fields CsvFieldMetrics[][]
---@return integer[]
function M._max_column_width(fields)
  local column_max_widths = {} --- @type integer[]
  for i = 1, #fields do
    for j = 1, #fields[i] do
      local width = fields[i][j].display_width
      if not column_max_widths[j] or width > column_max_widths[j] then
        column_max_widths[j] = width
      end
    end
  end
  return column_max_widths
end

--- compute csv metrics
---@param bufnr integer
---@param on_end fun(fields:CsvFieldMetrics,column_max_widths:number[])
---@param startlnum integer?
---@param endlnum integer?
---@param fields CsvFieldMetrics[][]?
function M.compute_csv_metrics(bufnr, on_end, startlnum, endlnum, fields)
  fields = fields or {}
  parser.iter_lines_async(bufnr, startlnum, endlnum, function(lnum, columns)
    fields[lnum] = {}
    for i, column in ipairs(columns) do
      local width = vim.fn.strdisplaywidth(column)
      fields[lnum][i] = {
        len = #column,
        display_width = width,
        is_number = tonumber(column) ~= nil,
      }
    end
  end, function()
    on_end(fields, M._max_column_width(fields))
  end)
end

return M
