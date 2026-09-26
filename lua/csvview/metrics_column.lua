-----------------------------------------------------------------------------
-- Column Tracker Module
-- Responsible for tracking column max widths and managing recalculation
-----------------------------------------------------------------------------

--- @class CsvView.ColumnTracker
--- @field private _columns CsvView.Metrics.Column[]
--- @field private _store CsvView.MetricsStore
local ColumnTracker = {}
ColumnTracker.__index = ColumnTracker

--- @class CsvView.Metrics.Column
--- @field max_width integer
--- @field max_row integer physical line number of the widest field
--- @field dirty boolean whether the column needs recalculation

--- Create new ColumnTracker instance
---@param store CsvView.MetricsStore
---@return CsvView.ColumnTracker
function ColumnTracker:new(store)
  return setmetatable({ _columns = {}, _store = store }, self)
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

--- Update column width for a field.
---@param col_idx integer 1-indexed column index
---@param lnum integer physical line number of the field
---@param width integer display width of the field
function ColumnTracker:update_width(col_idx, lnum, width)
  local column = self._columns[col_idx]
  if not column then
    column = { max_width = -1, max_row = 0, dirty = false }
    self._columns[col_idx] = column
  end

  if width > column.max_width then
    column.max_width = width
    column.max_row = lnum
  elseif column.max_row == lnum and width < column.max_width then
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

--- Mark the columns whose widest field is on the line, but which the line no longer has.
---
--- [MAX_FIELD_DELETION]
--- e.g.
--- before:
---    123456,123456,123456
---    123,123,123
--- after:
---    123456,123456
---    123,123,123
--- The third column must be recalculated.
---@param lnum integer
---@param prev_col0 integer
---@param prev_count integer
---@param col0 integer
---@param count integer
function ColumnTracker:mark_removed_fields(lnum, prev_col0, prev_count, col0, count)
  for col_idx = prev_col0 + 1, prev_col0 + prev_count do
    if col_idx <= col0 or col_idx > col0 + count then
      local column = self._columns[col_idx]
      if column and column.max_row == lnum then
        column.dirty = true
      end
    end
  end
end

--- Follow lines being inserted or removed.
---
--- Lines in `[first, first - delta)` are removed when `delta < 0`; the columns whose
--- widest field was on them are recalculated ([MAX_ROW_DELETION]). Lines from
--- `first` on (after the removed ones) move by `delta`.
---@param first integer
---@param delta integer
function ColumnTracker:shift_rows(first, delta)
  for _, column in pairs(self._columns) do
    if delta < 0 and column.max_row >= first and column.max_row < first - delta then
      column.dirty = true
    elseif column.max_row >= first then
      column.max_row = column.max_row + delta
    end
  end
end

--- Recalculate all dirty columns with a single scan of the store.
function ColumnTracker:recalculate_dirty()
  local dirty = {} ---@type integer[]
  for col_idx, column in pairs(self._columns) do
    if column.dirty then
      dirty[#dirty + 1] = col_idx
    end
  end
  if #dirty == 0 then
    return
  end

  local ndirty = #dirty
  local max_width, max_row = {}, {} ---@type integer[], integer[]
  for i = 1, ndirty do
    max_width[i] = -1
    max_row[i] = 0
  end

  local store = self._store
  local count, col0, base, width = store.count, store.col0, store.base, store.width
  for lnum = 1, store.n do
    local c = count[lnum]
    if c > 0 then
      local first = col0[lnum]
      local b = base[lnum]
      for i = 1, ndirty do
        local idx = dirty[i] - first - 1
        if idx >= 0 and idx < c then
          local w = width[b + idx]
          if w > max_width[i] then
            max_width[i] = w
            max_row[i] = lnum
          end
        end
      end
    end
  end

  for i = 1, ndirty do
    local col_idx = dirty[i]
    if max_row[i] > 0 then
      local column = self._columns[col_idx]
      column.max_width = max_width[i]
      column.max_row = max_row[i]
      column.dirty = false
    else
      -- No line has this column anymore
      self._columns[col_idx] = nil
    end
  end
end

return ColumnTracker
