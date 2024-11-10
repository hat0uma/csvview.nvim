local parser = require("csvview.parser")

--- @class CsvViewMetrics
--- @field public rows CsvViewMetrics.Row[]
--- @field public columns CsvViewMetrics.Column[]
--- @field private _bufnr integer
--- @field private _opts CsvViewOptions
local CsvViewMetrics = {}

--- @class CsvViewMetrics.Row
--- @field is_comment boolean
--- @field fields CsvFieldMetrics.Field[] | nil

--- @class CsvViewMetrics.Column
--- @field max_width integer

--- @class CsvFieldMetrics.Field
--- @field len integer
--- @field display_width integer
--- @field is_number boolean

function CsvViewMetrics:new(bufnr, opts)
  self.__index = self

  local obj = {}
  obj._bufnr = bufnr
  obj._opts = opts
  obj.rows = {}
  obj.columns = {}

  return setmetatable(obj, self)
end

function CsvViewMetrics:clear()
  self.rows = {}
  self.columns = {}
end

--- Update metrics for specified range
---@param first integer first line number
---@param last integer last line number
---@param last_updated integer current last updated line
---@param on_end fun()? callback for when the update is complete
function CsvViewMetrics:update(first, last, last_updated, on_end)
  if last_updated > last then
    local delta = last_updated - last
    for _ = 1, delta do
      table.insert(self.rows, last + 1, { fields = {} })
    end
  elseif last > last_updated then
    local delta = last - last_updated
    for _ = 1, delta do
      table.remove(self.rows, last_updated + 1)
    end
  end

  -- update metrics
  self:_compute(first + 1, last_updated, on_end)
end

--- Compute metrics for the entire buffer
---@param on_end fun()? callback for when the update is complete
function CsvViewMetrics:compute_buffer(on_end)
  self:_compute(nil, nil, on_end)
end

--- Compute metrics
---@param startlnum integer? if present, compute only specified range
---@param endlnum integer? if present, compute only specified range
---@param on_end fun()? callback for when the update is complete
function CsvViewMetrics:_compute(startlnum, endlnum, on_end)
  -- parse buffer and update metrics
  parser.iter_lines_async(self._bufnr, startlnum, endlnum, {
    on_line = function(lnum, is_comment, fields)
      if is_comment then
        self.rows[lnum] = { is_comment = is_comment, fields = nil }
        return
      end

      self.rows[lnum] = { is_comment = false, fields = {} }
      for i, field in ipairs(fields) do
        local width = vim.fn.strdisplaywidth(field)
        self.rows[lnum].fields[i] = {
          len = #field,
          display_width = width,
          is_number = tonumber(field) ~= nil,
        }
      end
    end,
    on_end = function()
      self:_update_column_metrics()
      if on_end then
        on_end()
      end
    end,
  }, self._opts)
end

--- Compute column metrics
function CsvViewMetrics:_update_column_metrics()
  --- @type CsvViewMetrics.Column[]
  local columns = {}
  for _, row in ipairs(self.rows) do
    if row.is_comment then
      goto continue
    end

    for j, field in ipairs(row.fields) do
      local width = field.display_width

      -- initialize column metrics
      if not columns[j] then
        columns[j] = { max_width = width }
      end

      -- update column max width
      if width > columns[j].max_width then
        columns[j].max_width = width
      end
    end

    ::continue::
  end
  self.columns = columns
end

return CsvViewMetrics
