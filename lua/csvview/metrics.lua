local parser = require("csvview.parser")

local nop = function() end

--- @class CsvView.Metrics
--- @field public rows CsvView.Metrics.Row[]
--- @field public columns CsvView.Metrics.Column[]
--- @field private _bufnr integer
--- @field private _opts CsvView.Options
local CsvViewMetrics = {}

--- @class CsvView.Metrics.Row
--- @field is_comment boolean?
--- @field fields CsvView.Metrics.Field[]

--- @class CsvView.Metrics.Column
--- @field max_width integer
--- @field max_row integer

--- @class CsvView.Metrics.Field
--- @field len integer
--- @field display_width integer
--- @field is_number boolean

--- Create new CsvViewMetrics instance
---@param bufnr integer
---@param opts CsvView.Options
---@return CsvView.Metrics
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
  for _ = 1, #self.rows do
    table.remove(self.rows)
  end

  for _ = 1, #self.columns do
    table.remove(self.columns)
  end
end

--- Compute metrics for the entire buffer
---@param on_end fun()? callback for when the update is complete
function CsvViewMetrics:compute_buffer(on_end)
  on_end = on_end or nop
  self:_compute_metrics(nil, nil, {}, on_end)
end

--- Update metrics for specified range
---
--- Metrics are optimized to recalculate only the changed range.
--- However, the entire column is recalculated in the following cases.
---   (1) If the line recorded as the maximum width of the column is deleted.
---       See: [MAX_ROW_DELETION] (in `_mark_recalculation_on_delete`)
---   (2) If a field was deleted and it was the maximum width in its column.
---       See: [MAX_FIELD_DELETION] (in `_mark_recalculation_on_decrease_fields`)
---   (3) If the maximum width has shrunk.
---       See: [SHRINK_WIDTH] (in `_adjust_column_metrics_for_row`)
---
---@param first integer first line number
---@param prev_last integer previous last line
---@param last integer current last line
---@param on_end fun()? callback for when the update is complete
function CsvViewMetrics:update(first, prev_last, last, on_end)
  on_end = on_end or nop

  ---@type table<integer,boolean>
  local recalculate_columns = {}

  -- print("update", first, prev_last, last)
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
---@param on_end fun() callback for when the update is complete
function CsvViewMetrics:_compute_metrics(startlnum, endlnum, recalculate_columns, on_end)
  -- Parse specified range and update metrics.
  parser.iter_lines_async(self._bufnr, startlnum, endlnum, {
    on_line = function(lnum, is_comment, fields)
      local prev_row = self.rows[lnum]

      -- Update row metrics and adjust column metrics
      self.rows[lnum] = self:_compute_metrics_for_row(is_comment, fields)
      self:_mark_recalculation_on_decrease_fields(lnum, prev_row, recalculate_columns)
      self:_adjust_column_metrics_for_row(lnum, recalculate_columns)
    end,
    on_end = function()
      -- Recalculate column metrics if necessary
      -- vim.print("recalculate_columns", recalculate_columns)
      for col_idx, _ in pairs(recalculate_columns) do
        self:_recalculate_column(col_idx)
      end

      -- notify the end of the update
      on_end()
    end,
  }, self._opts)
end

--- Compute row metrics
---@param is_comment boolean
---@param fields string[]
---@return CsvView.Metrics.Row
function CsvViewMetrics:_compute_metrics_for_row(is_comment, fields)
  if is_comment then
    return { is_comment = true, fields = {} }
  end

  -- Compute field metrics
  local row = { fields = {} } ---@type CsvView.Metrics.Row
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

--- Recalculate column metrics for the specified column
---@param col_idx integer
function CsvViewMetrics:_recalculate_column(col_idx)
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
  -- [MAX_ROW_DELETION]
  -- If the deleted line was the maximum line of the column, it is recalculated.
  -- e.g.
  -- before:
  --    123456,12,12 <- delete this line
  --    123,123,123
  -- after:
  --    123,123,123
  --
  -- -> prev_last = 1, last = 0
  -- In this case, the column metrics for the first column need to be recalculated.
  for col_idx, column in ipairs(self.columns) do
    if column.max_row > last and column.max_row <= prev_last then
      recalculate_columns[col_idx] = true
    end
  end
end

--- Mark column for recalculation on decrease fields
---@param row_idx integer
---@param prev_row CsvView.Metrics.Row | nil
---@param recalculate_columns table<integer,boolean>
function CsvViewMetrics:_mark_recalculation_on_decrease_fields(row_idx, prev_row, recalculate_columns)
  -- [MAX_FIELD_DELETION]
  -- If a field is deleted and it was the maximum width in its column, mark the column for recalculation.
  -- e.g.
  -- before:
  --    123456,123456,123456
  --    123,123,123
  -- after:
  --    123456,123456
  --    123,123,123
  --
  -- In this case, the column metrics for the third column need to be recalculated.
  if not prev_row then
    return
  end

  local row = self.rows[row_idx]

  for col_idx = #row.fields + 1, #prev_row.fields do
    -- Check if the column exists and if the current row was the maximum width row for this column.
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
    local column = self:_ensure_column(col_idx)
    local width = field.display_width

    if width > column.max_width then
      column.max_width = width
      column.max_row = row_idx
    elseif column.max_row == row_idx and width < column.max_width then
      -- [SHRINK_WIDTH] Mark for recalculation if max width shrinks
      recalculate_columns[col_idx] = true
    end
  end
end

--- Ensure column metrics
---@param col_idx integer
---@return CsvView.Metrics.Column
function CsvViewMetrics:_ensure_column(col_idx)
  if not self.columns[col_idx] then
    self.columns[col_idx] = { max_width = 0, max_row = 0 }
  end
  return self.columns[col_idx]
end

--- Add row placeholders
---@param prev_last integer
---@param num integer
function CsvViewMetrics:_add_row_placeholders(prev_last, num)
  for _ = 1, num do
    table.insert(self.rows, prev_last + 1, { fields = {} })
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
