local nop = function() end
local ColumnTracker = require("csvview.metrics_column")
local Row = require("csvview.metrics_row")
local RowMapper = require("csvview.metrics_row_mapper")

-----------------------------------------------------------------------------
-- Metrics class
-- Coordinates row storage, column tracking, and line mapping
-----------------------------------------------------------------------------

--- @class CsvView.Metrics
--- @field private _rows CsvView.Metrics.Row[]
--- @field private _columns CsvView.ColumnTracker
--- @field private _mapper CsvView.RowMapper
--- @field private _bufnr integer
--- @field private _opts CsvView.InternalOptions
--- @field private _parser CsvView.Parser
--- @field private _current_parse { cancelled: boolean }?
local CsvViewMetrics = {}

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

  -- Create row mapper with callbacks to access rows
  local get_row = function(lnum)
    return obj._rows[lnum]
  end
  local row_count = function()
    return #obj._rows
  end
  obj._columns = ColumnTracker:new(get_row, row_count)
  obj._mapper = RowMapper:new(get_row, row_count)
  return setmetatable(obj, self)
end

--- Clear metrics
function CsvViewMetrics:clear()
  for _ = 1, #self._rows do
    table.remove(self._rows)
  end
  self._columns:clear()
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
---@return CsvView.Metrics.Row?
function CsvViewMetrics:row(opts)
  assert(opts, "opts is required")
  assert(opts.lnum or opts.row_idx, "opts.lnum or opts.row_idx is required")
  assert(not (opts.lnum and opts.row_idx), "opts.lnum and opts.row_idx are mutually exclusive")

  if opts.lnum then
    return self._rows[opts.lnum]
  else
    return self._mapper:get_row_by_row_idx(opts.row_idx)
  end
end

--- Get the number of rows
---@return integer
function CsvViewMetrics:row_count()
  return #self._rows
end

--- Get column metrics
---@param col_idx 1-indexed column index
---@return CsvView.Metrics.Column?
function CsvViewMetrics:column(col_idx)
  return self._columns:get(col_idx)
end

--- Compute metrics for the entire buffer
---@param on_end fun(err:string|nil)? callback for when the update is complete
function CsvViewMetrics:compute_buffer(on_end)
  on_end = on_end or nop
  self:_compute_metrics(nil, nil, on_end)
end

--- Update metrics for specified range
---
--- Metrics are optimized to recalculate only the changed range.
--- However, the entire column is recalculated in the following cases.
---   (1) If the line recorded as the maximum width of the column is deleted.
---       See: [MAX_ROW_DELETION] (in ColumnTracker:mark_dirty_on_row_delete)
---   (2) If a field was deleted and it was the maximum width in its column.
---       See: [MAX_FIELD_DELETION] (in ColumnTracker:mark_dirty_on_field_decrease)
---   (3) If the maximum width has shrunk.
---       See: [SHRINK_WIDTH] (in ColumnTracker:update_width)
---
---@param first integer first line number
---@param prev_last integer previous last line
---@param last integer current last line
---@param on_end fun(err:string|nil)? callback for when the update is complete
function CsvViewMetrics:update(first, prev_last, last, on_end)
  on_end = on_end or nop

  if self._current_parse then
    self._current_parse.cancelled = true
  end
  self._current_parse = { cancelled = false }

  -- Get the range of affected lines
  local start_reparse, end_reparse = self:_calculate_reparse_range(first, prev_last, last)

  local delta = last - prev_last
  if delta > 0 then
    self:_add_row_placeholders(prev_last + 1, delta)
  elseif delta < 0 then
    self:_remove_rows(last + 1, math.abs(delta))
    self:_mark_recalculation_on_delete(prev_last, last)
  end

  -- update metrics
  self:_compute_metrics(start_reparse, end_reparse, on_end)
end

--- Calculate the range of logical CSV rows for the changed lines
---@param first integer first line number
---@param prev_last integer previous last line
---@param last integer current last line
---@return integer start_reparse start line number of the range to reparse
---@return integer end_reparse end line number of the range to reparse
function CsvViewMetrics:_calculate_reparse_range(first, prev_last, last)
  -- Calculate the range of logical CSV rows for the changed lines
  local start_reparse, end_reparse --- @type integer, integer
  if (first + 1) <= #self._rows then
    -- if adding a new row before the last row
    local field_start_lnum, field_end_lnum = self._mapper:get_logical_row_range(first + 1)
    start_reparse = field_start_lnum
    end_reparse = math.max(field_end_lnum, last)
  elseif first ~= 0 and first <= #self._rows then
    -- if adding a new row at the end of the last row
    local field_start_lnum, field_end_lnum = self._mapper:get_logical_row_range(first)
    start_reparse = field_start_lnum
    end_reparse = math.max(field_end_lnum, last)
  else
    start_reparse = first
    end_reparse = last
  end

  -- Extend the range to include the affected lines
  local row_delta = last - prev_last
  if row_delta > 0 then
    -- If rows were added, extend the end of the reparse range
    end_reparse = end_reparse + row_delta
  end

  -- Ensure the range is within bounds
  end_reparse = math.min(end_reparse, vim.api.nvim_buf_line_count(self._bufnr))
  return start_reparse, end_reparse
end

--- Compute metrics
---@param startlnum integer? if present, compute only specified range
---@param endlnum integer? if present, compute only specified range
---@param on_end fun(err:string|nil) callback for when the update is complete
function CsvViewMetrics:_compute_metrics(startlnum, endlnum, on_end)
  -- State for building rows from parse events
  local field_buffer = Row.FieldBuffer:new()
  local line_field_counts = {} ---@type integer[]
  local record_start_lnum = 0

  -- Parse using parse_records with event callbacks
  self._parser:parse_records(self._opts.parser.async_chunksize, {
    on_comment = function(lnum)
      local prev_row = self._rows[lnum]
      local row = Row.new_comment()
      self._rows[lnum] = row
      self:_mark_recalculation_on_decrease_fields(lnum, prev_row, row)
    end,

    on_record_start = function(lnum)
      -- clear record state
      record_start_lnum = lnum
      field_buffer:reset()
      for k in pairs(line_field_counts) do
        line_field_counts[k] = nil
      end
    end,

    on_field = function(_, lnum, line, offset, endpos)
      local len = endpos - offset -- endpos is 1-based end position, offset is 0-based start
      local text = string.sub(line, offset + 1, endpos)
      local display_width = vim.fn.strdisplaywidth(text, offset)
      local is_number = tonumber(text) ~= nil
      field_buffer:add(offset, len, display_width, is_number)

      -- field count per lines
      local rel_idx = lnum - record_start_lnum
      line_field_counts[rel_idx] = (line_field_counts[rel_idx] or 0) + 1
    end,

    on_record_end = function(record_start, record_end, terminated)
      local new_endlnum = nil
      local is_multiline = record_start ~= record_end
      local current_skipped = 0

      -- Track buffer offset as we consume fields for each row
      local current_buffer_offset = 0
      for lnum = record_start, record_end do
        local prev_row = self._rows[lnum]

        local rel_idx = lnum - record_start
        local field_count = line_field_counts[rel_idx] or 0
        local skipped_ncol = current_skipped

        -- Create appropriate row type
        local new_row --- @type CsvView.Metrics.Row
        if not is_multiline then
          new_row = Row.new_singleline(field_count)
        elseif lnum == record_start then
          local endloffset = record_end - record_start
          new_row = Row.new_multiline_start(field_count, endloffset, terminated)
        else
          local start_loffset = lnum - record_start
          local end_loffset = record_end - lnum
          new_row = Row.new_multiline_continuation(field_count, start_loffset, end_loffset, skipped_ncol, terminated)
        end

        -- Copy fields from buffer to row
        field_buffer:copy_to_row(new_row, current_buffer_offset, field_count)
        current_buffer_offset = current_buffer_offset + field_count

        -- update skipped count
        if field_count > 0 then
          current_skipped = current_skipped + (field_count - 1)
        end

        self._rows[lnum] = new_row
        if prev_row and prev_row.type == "multiline_start" and new_row.type == "multiline_continuation" then
          -- If the structure of the multi-line field is broken, it affects all subsequent rows,
          -- so all rows need to be recalculated.
          new_endlnum = vim.api.nvim_buf_line_count(self._bufnr) - 1
        end

        self:_mark_recalculation_on_decrease_fields(lnum, prev_row, new_row)
        self:_update_column_metrics_for_row(lnum)
      end

      return new_endlnum
    end,

    on_end = function(err)
      if err then
        on_end(err)
        return
      end

      -- Recalculate dirty columns
      self._columns:recalculate_dirty()
      on_end()
    end,
  }, startlnum, endlnum, self._current_parse)
end

--- Mark column for recalculation on delete
---@param prev_last integer
---@param last integer
function CsvViewMetrics:_mark_recalculation_on_delete(prev_last, last)
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
  for col_idx, column in self._columns:iter() do
    if column.max_row > last and column.max_row <= prev_last then
      self._columns:mark_dirty(col_idx)
    end
  end
end

--- Mark column for recalculation on decrease fields
---@param row_idx integer
---@param prev_row CsvView.Metrics.Row | nil
---@param curr_row CsvView.Metrics.Row
function CsvViewMetrics:_mark_recalculation_on_decrease_fields(row_idx, prev_row, curr_row)
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

  for col_idx, _ in prev_row:iter() do
    -- Check if the column exists and if the current row was the maximum width row for this column.
    local column = self._columns:get(col_idx)
    if column and column.max_row == row_idx then
      local current_field = curr_row:field(col_idx)
      if not current_field then
        self._columns:mark_dirty(col_idx)
      end
    end
  end
end

--- Adjust column metrics for the specified row
---@param row_idx integer row index
function CsvViewMetrics:_update_column_metrics_for_row(row_idx)
  local row = self._rows[row_idx]

  -- Update column metrics
  -- [SHRINK_WIDTH] is handled in ColumnTracker:update_width
  -- If the max width shrinks, the column is marked for recalculation.
  for col_idx, field in row:iter() do
    self._columns:update_width(col_idx, row_idx, field.display_width)
  end
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
    self._rows[i] = Row.new_singleline(0)
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

--- Find the start of the logical row containing the given physical line number
---@param lnum integer physical line number
---@return integer logical_start_lnum, integer logical_end_lnum
function CsvViewMetrics:get_logical_row_range(lnum)
  return self._mapper:get_logical_row_range(lnum)
end

--- Get logical row number from physical line number
---@param physical_lnum integer Physical line number (1-based)
---@return integer? logical_row_num Logical row number (1-based)
function CsvViewMetrics:get_logical_row_idx(physical_lnum)
  return self._mapper:physical_to_logical(physical_lnum)
end

--- Get the physical line number for a logical row number
---@param logical_row_num integer Logical row number (1-based)
---@return integer? physical_lnum Physical line number (1-based)
function CsvViewMetrics:get_physical_line_number(logical_row_num)
  return self._mapper:logical_to_physical(logical_row_num)
end

--- Get field ranges for a logical row containing the given physical line number.
---@param opts { lnum?: integer, row_idx?:integer } specify either `lnum` or `row_idx`
---@return CsvView.Metrics.LogicalFieldRange[] ranges List of logical field ranges for the row
function CsvViewMetrics:get_logical_row_fields(opts)
  local lnum = opts.lnum or self._mapper:logical_to_physical(opts.row_idx)
  if not lnum then
    error(string.format("Invalid lnum or row_idx: lnum=%s, row_idx=%s", opts.lnum, opts.row_idx))
  end
  return self._mapper:get_logical_row_fields(lnum)
end

--- Get the logical field range for a given line number and byte offset.
---@param lnum integer Line number (1-based)
---@param offset integer Byte offset within the line
---@return integer col_idx Column index of the field containing the byte offset
---@return CsvView.Metrics.LogicalFieldRange range Logical field range for the given line and offset
function CsvViewMetrics:get_logical_field_by_offet(lnum, offset)
  return self._mapper:get_logical_field_by_offset(lnum, offset)
end

return CsvViewMetrics
