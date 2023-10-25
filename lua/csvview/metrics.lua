local parser = require("csvview.parser")
local co = coroutine
local M = {}

--- @class CsvFieldMetrics
--- @field len integer
--- @field display_width integer
--- @field is_number boolean

--- resume
---@param t thread
local function resume(t)
  local status, value = co.resume(t)
  if not status then
    error(value)
  end
  if co.status(t) ~= "dead" then
    vim.schedule(function()
      resume(t)
    end)
  end
end

--- compute csv metrics
---@param bufnr integer
---@param cb fun(csv:{ column_max_widths:number[],fields:CsvFieldMetrics[][] })
---@param startlnum integer?
---@param endlnum integer?
---@param fields CsvFieldMetrics[][]?
function M.compute_csv_metrics(bufnr, cb, startlnum, endlnum, fields)
  local thread = co.create(function() ---@async
    --- @type { column_max_widths:number[],fields:CsvFieldMetrics[][] }
    local csv = { column_max_widths = {}, fields = fields or {} }

    --- analyze field
    for lnum, columns in parser.iter_lines(bufnr, startlnum, endlnum) do
      csv.fields[lnum] = {}
      for i, column in ipairs(columns) do
        local width = vim.fn.strdisplaywidth(column)
        csv.fields[lnum][i] = {
          len = #column,
          display_width = width,
          is_number = tonumber(column) ~= nil,
        }
      end
      if co.running() then
        co.yield()
      end
    end

    --- update column max width
    for i = 1, #csv.fields do
      for j = 1, #csv.fields[i] do
        local width = csv.fields[i][j].display_width
        if not csv.column_max_widths[j] or width > csv.column_max_widths[j] then
          csv.column_max_widths[j] = width
        end
      end
    end
    cb(csv)
  end)

  resume(thread)
end

return M
