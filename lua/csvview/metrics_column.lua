-----------------------------------------------------------------------------
-- Column Tracker Module
-- Responsible for tracking column max widths and managing recalculation
-----------------------------------------------------------------------------

--- @class CsvView.ColumnTracker
--- @field private _columns CsvView.Metrics.Column[]
--- @field private _get_row fun(lnum: integer): CsvView.Metrics.Row? function to get row by physical line number
--- @field private _row_count fun(): integer function to get total row count
local ColumnTracker = {}

--- @class CsvView.Metrics.Column
--- @field max_width integer
--- @field max_row integer
--- @field dirty boolean? whether the column needs recalculation

--- Create new ColumnTracker instance
---@param get_row fun(lnum: integer): CsvView.Metrics.Row? function to get row by physical line number
---@param row_count fun(): integer function to get total row count
---@return CsvView.ColumnTracker
function ColumnTracker:new(get_row, row_count)
  self.__index = self
  local obj = {
    _columns = {},
    _get_row = get_row,
    _row_count = row_count,
  }
  return setmetatable(obj, self)
end

--- Clear all column data
function ColumnTracker:clear()
  self._columns = {}
end

--- Get column metrics
---@param col_idx integer 1-indexed column index
---@return CsvView.Metrics.Column?
function ColumnTracker:get(col_idx)
  return self._columns[col_idx]
end

--- Get number of columns
---@return integer
function ColumnTracker:count()
  local max_col = 0
  for col_idx, _ in pairs(self._columns) do
    if col_idx > max_col then
      max_col = col_idx
    end
  end
  return max_col
end

--- Ensure column exists
---@param col_idx integer
---@return CsvView.Metrics.Column
function ColumnTracker:ensure(col_idx)
  if not self._columns[col_idx] then
    self._columns[col_idx] = { max_width = 0, max_row = 0, dirty = false }
  end
  return self._columns[col_idx]
end

--- Update column width for a specific row
--- Returns true if the global max width increased
---@param col_idx integer 1-indexed column index
---@param row_idx integer 1-indexed row index
---@param width integer display width of the field
function ColumnTracker:update_width(col_idx, row_idx, width)
  local column = self:ensure(col_idx)

  if width > column.max_width then
    column.max_width = width
    column.max_row = row_idx
  elseif column.max_row == row_idx and width < column.max_width then
    -- [SHRINK_WIDTH] Mark for recalculation if max width shrinks
    column.dirty = true
  end
end

--- Mark a column as dirty (needs recalculation)
---@param col_idx integer
function ColumnTracker:mark_dirty(col_idx)
  local column = self._columns[col_idx]
  if column then
    column.dirty = true
  end
end

--- Iterate over all columns
---@return fun(): integer?, CsvView.Metrics.Column?
---@return CsvView.Metrics.Column[]
function ColumnTracker:iter()
  return pairs(self._columns)
end

--- Recalculate a column's max width by scanning all rows
---@param col_idx integer
function ColumnTracker:recalculate(col_idx)
  local max_width = 0
  local max_row = nil

  for row_idx = 1, self._row_count() do
    local row = self._get_row(row_idx)
    local field = row and row:field(col_idx) or nil
    if field and field.display_width > max_width then
      max_width = field.display_width
      max_row = row_idx
    end
  end

  local column = self._columns[col_idx]
  if max_row then
    column.max_width = max_width
    column.max_row = max_row
    column.dirty = false
  else
    -- Remove column if it is empty
    self._columns[col_idx] = nil
  end
end

--- Recalculate all dirty columns
function ColumnTracker:recalculate_dirty()
  for col_idx, column in pairs(self._columns) do
    if column.dirty then
      self:recalculate(col_idx)
    end
  end
end

return ColumnTracker
