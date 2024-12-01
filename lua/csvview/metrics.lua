local parser = require("csvview.parser")

--- @class CsvViewMetrics
--- @field public rows CsvViewMetrics.Row[]
--- @field public columns CsvViewMetrics.Column[]
--- @field private _bufnr integer
--- @field private _opts CsvViewOptions
local CsvViewMetrics = {}

--- @class CsvViewMetrics.Row
--- @field is_comment boolean
--- @field fields CsvFieldMetrics.Field[]

--- @class CsvViewMetrics.Column
--- @field max_width integer
--- @field max_row integer

--- @class CsvFieldMetrics.Field
--- @field len integer
--- @field display_width integer
--- @field is_number boolean

--- Create new CsvViewMetrics instance
---@param bufnr integer
---@param opts CsvViewOptions
---@return CsvViewMetrics
function CsvViewMetrics:new(bufnr, opts)
  self.__index = self

  local obj = {}
  obj._bufnr = bufnr
  obj._opts = opts
  obj.rows = {}
  obj.columns = {}

  return setmetatable(obj, self)
end

--- Clear metrics
function CsvViewMetrics:clear()
  self.rows = {}
  self.columns = {}
end

--- Compute metrics for the entire buffer
---@param on_end fun()? callback for when the update is complete
function CsvViewMetrics:compute_buffer(on_end)
  self:_compute_metrics(nil, nil, {}, on_end)
end

--- Update metrics for specified range
---
--- Metrics are optimized to recalculate only the changed range.
--- However, the entire column is recalculated in the following cases.
---   (1) If the line recorded as the maximum width of the column is deleted.
---   (2) If the maximum width has shrunk.
---
---@param first integer first line number
---@param prev_last integer previous last line
---@param last integer current last line
---@param on_end fun()? callback for when the update is complete
function CsvViewMetrics:update(first, prev_last, last, on_end)
  ---@type table<integer,boolean>
  local recalculate_columns = {}

  local delta = last - prev_last
  if delta > 0 then
    self:_add_row_placeholders(prev_last, delta)
  elseif delta < 0 then
    self:_remove_rows(last, math.abs(delta))
    self:_mark_recalculation_on_delete(prev_last, last, recalculate_columns)
  end

  -- update metrics
  self:_compute_metrics(first + 1, last, recalculate_columns, on_end)
end

--- Compute metrics
---
---@param startlnum integer? if present, compute only specified range
---@param endlnum integer? if present, compute only specified range
---@param recalculate_columns table<integer,boolean> recalculate specified columns
---@param on_end fun()? callback for when the update is complete
function CsvViewMetrics:_compute_metrics(startlnum, endlnum, recalculate_columns, on_end)
  -- Parse specified range and update metrics.
  parser.iter_lines_async(self._bufnr, startlnum, endlnum, {
    on_line = function(lnum, is_comment, fields)
      local prev_row = self.rows[lnum]

      -- Update row metrics and adjust column metrics
      self.rows[lnum] = self:_compute_metrics_for_row(is_comment, fields)
      if prev_row then
        self:_mark_recalculation_on_decrease_fields(lnum, prev_row, recalculate_columns)
      end
      self:_adjust_column_metrics_for_row(lnum, recalculate_columns)
    end,
    on_end = function()
      -- Recalculate column metrics if necessary
      -- vim.print("recalculate_columns", recalculate_columns)
      for col_idx, _ in pairs(recalculate_columns) do
        self:_compute_metrics_for_column(col_idx)
      end

      if on_end then
        on_end()
      end
    end,
  }, self._opts)
end

--- Compute row metrics
---@param is_comment boolean
---@param fields string[]
---@return CsvViewMetrics.Row
function CsvViewMetrics:_compute_metrics_for_row(is_comment, fields)
  if is_comment then
    return { is_comment = true, fields = {} }
  end

  -- Compute field metrics
  local row = { is_comment = false, fields = {} } ---@type CsvViewMetrics.Row
  for _, field in ipairs(fields) do
    local width = vim.fn.strdisplaywidth(field)
    table.insert(row.fields, {
      len = #field,
      display_width = width,
      is_number = tonumber(field) ~= nil,
    })
  end
  return row
end

--- Compute column metrics for the specified column
---@param col_idx integer
function CsvViewMetrics:_compute_metrics_for_column(col_idx)
  local max_width = 0
  local max_row = nil

  -- Find the maximum width in the column
  for row_idx, row in ipairs(self.rows) do
    if not row.is_comment and row.fields[col_idx] then
      local width = row.fields[col_idx].display_width
      if width > max_width then
        max_width = width
        max_row = row_idx
      end
    end
  end

  if max_row then
    -- Update column metrics
    self.columns[col_idx].max_width = max_width
    self.columns[col_idx].max_row = max_row
  else
    -- Remove column if it is empty
    self.columns[col_idx] = nil
  end
end

--- Mark column for recalculation on delete
---@param prev_last integer
---@param last integer
---@param recalculate_columns table<integer,boolean>
function CsvViewMetrics:_mark_recalculation_on_delete(prev_last, last, recalculate_columns)
  for col_idx, column in ipairs(self.columns) do
    -- If the deleted line was the maximum line of the column, it is recalculated.
    if column.max_row > last and column.max_row <= prev_last then
      recalculate_columns[col_idx] = true
    end
  end
end

--- Mark column for recalculation on decrease fields
---@param row_idx integer
---@param prev_row CsvViewMetrics.Row
---@param recalculate_columns table<integer,boolean>
function CsvViewMetrics:_mark_recalculation_on_decrease_fields(row_idx, prev_row, recalculate_columns)
  local row = self.rows[row_idx]

  -- If the number of fields has decreased, recalculate the columns from that point on.
  for col_idx = #row.fields + 1, #prev_row.fields do
    if self.columns[col_idx] and self.columns[col_idx].max_row == row_idx then
      recalculate_columns[col_idx] = true
    end
  end
end

--- Adjust column metrics for the specified row
---@param row_idx integer row index
---@param recalculate_columns table<integer,boolean> recalculate columns
function CsvViewMetrics:_adjust_column_metrics_for_row(row_idx, recalculate_columns)
  local row = self.rows[row_idx]

  -- Update column metrics
  for col_idx, field in ipairs(row.fields) do
    local column = self.columns[col_idx]
    local width = field.display_width

    -- Initialize column metrics
    if not column then
      self.columns[col_idx] = { max_width = width, max_row = row_idx }
    elseif width > column.max_width then
      column.max_width = width
      column.max_row = row_idx
    elseif column.max_row == row_idx and width < column.max_width then
      -- Mark for recalculation if max width shrinks
      recalculate_columns[col_idx] = true
    end
  end
end

--- Add row placeholders
---@param prev_last integer
---@param num integer
function CsvViewMetrics:_add_row_placeholders(prev_last, num)
  for _ = 1, num do
    table.insert(self.rows, prev_last + 1, { is_comment = false, fields = {} })
  end
end

--- Remove rows
---@param last integer
---@param num integer
function CsvViewMetrics:_remove_rows(last, num)
  for _ = 1, num do
    table.remove(self.rows, last + 1)
  end
end

return CsvViewMetrics
