local nop = function() end

--- @class CsvView.Metrics.Row
--- @field is_comment boolean
--- @field fields CsvView.Metrics.Field[]
local CsvViewMetricsRow = {}

--- Create a new CsvView.Metrics.Row instance
---@param is_comment boolean
---@param fields CsvView.Parser.FieldInfo[]
---@return CsvView.Metrics.Row
function CsvViewMetricsRow:new(is_comment, fields)
  self.__index = self

  local obj = {}
  obj.is_comment = is_comment
  obj.fields = fields or {}
  setmetatable(obj, self)
  return obj
end

--- Get field by byte offset
---@param offset integer
---@return integer column_idx
---@return CsvView.Metrics.Field field
function CsvViewMetricsRow:get_field_by_offset(offset)
  local len = #self.fields
  for i, field in ipairs(self.fields) do
    if offset < field.offset then
      return i - 1, self.fields[i - 1]
    end
  end

  return len, self.fields[len]
end

--- @class CsvView.Metrics
--- @field private _rows CsvView.Metrics.Row[]
--- @field private _columns CsvView.Metrics.Column[]
--- @field private _bufnr integer
--- @field private _opts CsvView.InternalOptions
--- @field private _parser CsvView.Parser
local CsvViewMetrics = {}

--- @class CsvView.Metrics.Column
--- @field max_width integer
--- @field max_row integer

--- @class CsvView.Metrics.Field
--- @field offset integer
--- @field len integer
--- @field display_width integer
--- @field is_number boolean

--- Create new CsvViewMetrics instance
---@param bufnr integer
---@param opts CsvView.InternalOptions
---@param parser CsvView.Parser
---@return CsvView.Metrics
function CsvViewMetrics:new(bufnr, opts, parser)
  self.__index = self

  local obj = {}
  obj._bufnr = bufnr
  obj._opts = opts
  obj._parser = parser
  obj._rows = {}
  obj._columns = {}

  return setmetatable(obj, self)
end

--- Clear metrics
function CsvViewMetrics:clear()
  for _ = 1, #self._rows do
    table.remove(self._rows)
  end

  for _ = 1, #self._columns do
    table.remove(self._columns)
  end
end

---
---Options for getting row metrics
---
---@class CsvView.Metrics.RowGetOpts
---
---1-indexed line number. `lnum` is used when `row_idx` is not specified.
---TODO: Currently, `lnum` is same as `row_idx` because multi-line fields are not supported.
---@field lnum integer?
---
---1-indexed csv row index. `row_idx` is used when `lnum` is not specified.
---@field row_idx integer?
---

--- Get row metrics
---@param opts CsvView.Metrics.RowGetOpts
---@return CsvView.Metrics.Row
function CsvViewMetrics:row(opts)
  assert(opts, "opts is required")
  assert(opts.lnum or opts.row_idx, "opts.lnum or opts.row_idx is required")
  assert(not (opts.lnum and opts.row_idx), "opts.lnum and opts.row_idx are mutually exclusive")

  if opts.lnum then
    return self:_get_row_by_lnum(opts.lnum)
  else
    return self:_get_row_by_row_idx(opts.row_idx)
  end
end

--- Get the number of rows
---@return integer
function CsvViewMetrics:row_count()
  return #self._rows
end

--- Get column metrics
---@param col_idx 1-indexed column index
---@return CsvView.Metrics.Column
function CsvViewMetrics:column(col_idx)
  if not self._columns[col_idx] then
    error(string.format("Column out of bounds col_idx=%d", col_idx))
  end
  return self._columns[col_idx]
end

--- Compute metrics for the entire buffer
---@param on_end fun(err:string|nil)? callback for when the update is complete
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
---@param on_end fun(err:string|nil)? callback for when the update is complete
function CsvViewMetrics:update(first, prev_last, last, on_end)
  on_end = on_end or nop

  ---@type table<integer,boolean>
  local recalculate_columns = {}

  -- print("update", first, prev_last, last)
  local delta = last - prev_last
  if delta > 0 then
    self:_add_row_placeholders(prev_last + 1, delta)
  elseif delta < 0 then
    self:_remove_rows(last + 1, math.abs(delta))
    self:_mark_recalculation_on_delete(prev_last, last, recalculate_columns)
  end

  -- update metrics
  self:_compute_metrics(first + 1, last, recalculate_columns, on_end)
end

--- Get row metrics by line number
---@param lnum integer 1-indexed line number
---@return CsvView.Metrics.Row
function CsvViewMetrics:_get_row_by_lnum(lnum)
  -- TODO: This function needs to be modified if considering multi-line fields.
  if not self._rows[lnum] then
    error(string.format("Row out of bounds lnum=%d", lnum))
  end
  return self._rows[lnum]
end

--- Get row metrics by CSV row index
---@param row_idx integer 1-indexed CSV row index
---@return CsvView.Metrics.Row
function CsvViewMetrics:_get_row_by_row_idx(row_idx)
  if not self._rows[row_idx] then
    error(string.format("Row out of bounds row_idx=%d", row_idx))
  end
  return self._rows[row_idx]
end

--- Compute metrics
---
---@param startlnum integer? if present, compute only specified range
---@param endlnum integer? if present, compute only specified range
---@param recalculate_columns table<integer,boolean> recalculate specified columns
---@param on_end fun(err:string|nil) callback for when the update is complete
function CsvViewMetrics:_compute_metrics(startlnum, endlnum, recalculate_columns, on_end)
  -- Parse specified range and update metrics.
  self._parser:parse_lines({
    on_line = function(lnum, is_comment, fields)
      local prev_row = self._rows[lnum]

      -- Update row metrics and adjust column metrics
      self._rows[lnum] = self:_compute_metrics_for_row(lnum, is_comment, fields)
      self:_mark_recalculation_on_decrease_fields(lnum, prev_row, recalculate_columns)
      self:_adjust_column_metrics_for_row(lnum, recalculate_columns)
    end,
    on_end = function(err)
      if err then
        on_end(err)
        return
      end

      -- Recalculate column metrics if necessary
      -- vim.print("recalculate_columns", recalculate_columns)
      for col_idx, _ in pairs(recalculate_columns) do
        self:_recalculate_column(col_idx)
      end

      -- notify the end of the update
      on_end()
    end,
  }, startlnum, endlnum)
end

--- Compute row metrics
---@param lnum integer line number
---@param is_comment boolean
---@param fields CsvView.Parser.FieldInfo[]
---@return CsvView.Metrics.Row
function CsvViewMetrics:_compute_metrics_for_row(lnum, is_comment, fields)
  local row = CsvViewMetricsRow:new(is_comment, {})
  if is_comment then
    return row
  end

  -- Compute field metrics
  for _, field in ipairs(fields) do
    local width = self:_field_display_width(field)
    table.insert(row.fields, {
      offset = field.start_pos - 1,
      len = #field.text,
      display_width = width,
      is_number = tonumber(field.text) ~= nil,
    })
  end
  return row
end

--- Get the display width of the field
---@param field CsvView.Parser.FieldInfo
---@return integer
function CsvViewMetrics:_field_display_width(field)
  local text = field.text
  local max_width ---@type integer
  if type(text) == "table" then
    -- This is multi-line field. Get the width of the longest line.
    for _, line in ipairs(text) do
      local line_width = vim.fn.strdisplaywidth(line)
      if line_width > max_width then
        max_width = line_width
      end
    end
  else
    max_width = vim.fn.strdisplaywidth(text)
  end

  return max_width
end

--- Recalculate column metrics for the specified column
---@param col_idx integer
function CsvViewMetrics:_recalculate_column(col_idx)
  local max_width = 0
  local max_row = nil

  -- Find the maximum width in the column
  for row_idx, row in ipairs(self._rows) do
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
    self._columns[col_idx].max_width = max_width
    self._columns[col_idx].max_row = max_row
  else
    -- Remove column if it is empty
    self._columns[col_idx] = nil
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
  for col_idx, column in ipairs(self._columns) do
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

  local row = self._rows[row_idx]

  for col_idx = #row.fields + 1, #prev_row.fields do
    -- Check if the column exists and if the current row was the maximum width row for this column.
    if self._columns[col_idx] and self._columns[col_idx].max_row == row_idx then
      recalculate_columns[col_idx] = true
    end
  end
end

--- Adjust column metrics for the specified row
---@param row_idx integer row index
---@param recalculate_columns table<integer,boolean> recalculate columns
function CsvViewMetrics:_adjust_column_metrics_for_row(row_idx, recalculate_columns)
  local row = self._rows[row_idx]

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
  if not self._columns[col_idx] then
    self._columns[col_idx] = { max_width = 0, max_row = 0 }
  end
  return self._columns[col_idx]
end

--- Add row placeholders
---@param start integer
---@param num integer
function CsvViewMetrics:_add_row_placeholders(start, num)
  --
  -- This function is equivalent to the following code, but is more efficient when editing large buffers.
  --
  -- for i = 1, num do
  --   table.insert( self.rows, start, <placeholder> )
  -- end
  --

  local len = #self._rows
  for i = len, start, -1 do
    self._rows[i + num] = self._rows[i]
  end
  for i = start, start + num - 1 do
    self._rows[i] = CsvViewMetricsRow:new(false, {})
  end
end

--- Remove rows
---@param start integer
---@param num integer
function CsvViewMetrics:_remove_rows(start, num)
  --
  -- This function is equivalent to the following code, but is more efficient when editing large buffers.
  --
  -- for i = 1, num do
  --   table.remove( self.rows, start )
  -- end
  --

  local len = #self._rows
  for i = start, len do
    self._rows[i] = self._rows[i + num]
    self._rows[i + num] = nil
  end
end

return CsvViewMetrics
