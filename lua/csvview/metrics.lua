local strings = require("csvview.strings")
local nop = function() end
local ColumnTracker = require("csvview.metrics_column")
local Row = require("csvview.metrics_row")
local RowMapper = require("csvview.metrics_row_mapper")
local Store = require("csvview.metrics_store")

local KIND = Store.KIND
local display_width = strings.display_width
local is_number = strings.is_number

-----------------------------------------------------------------------------
-- Metrics class
-- Builds the store from parser events, and keeps column widths up to date
-----------------------------------------------------------------------------

--- @class CsvView.Metrics
--- @field store CsvView.MetricsStore read-only for callers
--- @field private _columns CsvView.ColumnTracker
--- @field private _mapper CsvView.RowMapper
--- @field private _bufnr integer
--- @field private _opts CsvView.InternalOptions
--- @field private _parser CsvView.Parser
--- @field private _current_parse { cancelled: boolean }?
local CsvViewMetrics = {}
CsvViewMetrics.__index = CsvViewMetrics
CsvViewMetrics.KIND = KIND

--- Create new CsvViewMetrics instance
---@param bufnr integer
---@param opts CsvView.InternalOptions
---@param parser CsvView.Parser
---@return CsvView.Metrics
function CsvViewMetrics:new(bufnr, opts, parser)
  local obj = setmetatable({}, self)
  obj._bufnr = bufnr
  obj._opts = opts
  obj._parser = parser
  obj.store = Store.new()
  obj._columns = ColumnTracker:new(obj.store)
  obj._mapper = RowMapper:new(obj.store)
  return obj
end

--- Clear metrics
function CsvViewMetrics:clear()
  self.store:clear()
  self._columns:clear()
end

---
---Options for getting row metrics
---
---@class CsvView.Metrics.RowGetOpts
---
---1-indexed line number. `lnum` is used when `row_idx` is not specified.
---@field lnum integer?
---
---1-indexed csv row index (comment lines are not counted). `row_idx` is used when `lnum` is not specified.
---@field row_idx integer?
---

--- Get row metrics.
--- The returned row is a snapshot, valid until the next metrics update.
---@param opts CsvView.Metrics.RowGetOpts
---@return CsvView.Metrics.Row?
function CsvViewMetrics:row(opts)
  assert(opts, "opts is required")
  assert(opts.lnum or opts.row_idx, "opts.lnum or opts.row_idx is required")
  assert(not (opts.lnum and opts.row_idx), "opts.lnum and opts.row_idx are mutually exclusive")

  local lnum = opts.lnum or self._mapper:row_idx_to_lnum(opts.row_idx)
  if not lnum then
    return nil
  end
  return Row.new(self.store, lnum)
end

--- Get the number of rows (physical lines)
---@return integer
function CsvViewMetrics:row_count()
  return self.store.n
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
---       See: [MAX_ROW_DELETION] (in ColumnTracker:shift_rows)
---   (2) If a field was deleted and it was the maximum width in its column.
---       See: [MAX_FIELD_DELETION] (in ColumnTracker:mark_removed_fields)
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

  -- While the buffer is still being parsed for the first time, the store only
  -- holds the lines parsed so far. Continue from its end so lines stay in order.
  local store = self.store
  start_reparse = math.min(start_reparse, store.n + 1)

  local delta = last - prev_last
  if delta > 0 and prev_last <= store.n then
    store:insert_lines(prev_last + 1, delta)
    self._columns:shift_rows(prev_last + 1, delta)
  elseif delta < 0 then
    store:remove_lines(last + 1, -delta)
    self._columns:shift_rows(last + 1, delta)
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
  if (first + 1) <= self.store.n then
    -- if adding a new row before the last row
    local field_start_lnum, field_end_lnum = self._mapper:get_logical_row_range(first + 1)
    start_reparse = field_start_lnum
    end_reparse = math.max(field_end_lnum, last)
  elseif first ~= 0 and first <= self.store.n then
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
  local store = self.store
  local columns = self._columns

  -- State of the record being parsed, per line relative to its first line.
  local record_start = 0
  local last_rel = -1 -- last line of the record that has a field so far
  local line_base = {} ---@type integer[] pool index of the first field of the line
  local line_count = {} ---@type integer[] number of fields on the line
  local line_col0 = {} ---@type integer[] column index of the first field on the line, minus 1

  --- Replace the layout of a line, keeping column widths up to date.
  local function set_line(lnum, kind, base, count, col0, rel, span, term)
    if store:has_line(lnum) then
      columns:mark_removed_fields(lnum, store.col0[lnum], store.count[lnum], col0, count)
    end
    store:set_line(lnum, kind, base, count, col0, rel, span, term)

    -- [SHRINK_WIDTH] is handled in ColumnTracker:update_width
    local width = store.width
    for i = 0, count - 1 do
      columns:update_width(col0 + i + 1, lnum, width[base + i])
    end
  end

  -- The range to parse. It grows while lines past it still belong to a record
  -- that no longer exists (see `extend_over_stale_lines`).
  local range_end = endlnum or vim.api.nvim_buf_line_count(self._bufnr)

  --- A line after a record can never continue it. If the line after `lnum` is still
  --- recorded as a continuation, it belongs to a record that this parse has
  --- changed, so keep parsing until the stale lines are gone.
  ---@param lnum integer last line of the record just parsed
  ---@return integer range_end
  local function extend_over_stale_lines(lnum)
    local next_lnum = lnum + 1
    if store:has_line(next_lnum) and store.kind[next_lnum] == KIND.MULTILINE_CONTINUATION then
      range_end = math.max(range_end, next_lnum)
    end
    return range_end
  end

  self._parser:parse_records(self._opts.parser.async_chunksize, {
    on_comment = function(lnum)
      set_line(lnum, KIND.COMMENT, 0, 0, 0, 0, 0, true)
      return extend_over_stale_lines(lnum)
    end,

    on_record_start = function(lnum)
      record_start = lnum
      last_rel = -1
    end,

    on_field = function(col_idx, lnum, line, offset, endpos)
      local idx = store:push_field(
        offset,
        endpos - offset, -- endpos is 1-based end position, offset is 0-based start
        display_width(line, offset, endpos),
        is_number(line, offset, endpos)
      )

      local rel = lnum - record_start
      if rel ~= last_rel then
        last_rel = rel
        line_base[rel] = idx
        line_count[rel] = 1
        line_col0[rel] = col_idx - 1
      else
        line_count[rel] = line_count[rel] + 1
      end
    end,

    on_record_end = function(record_start_lnum, record_end_lnum, terminated)
      local is_multiline = record_start_lnum ~= record_end_lnum

      for lnum = record_start_lnum, record_end_lnum do
        local rel = lnum - record_start_lnum
        local kind ---@type integer
        if not is_multiline then
          kind = KIND.SINGLELINE
        elseif rel == 0 then
          kind = KIND.MULTILINE_START
        else
          kind = KIND.MULTILINE_CONTINUATION
        end

        if rel <= last_rel then
          set_line(lnum, kind, line_base[rel], line_count[rel], line_col0[rel], rel, record_end_lnum - lnum, terminated)
        else
          -- line without fields (an empty line)
          set_line(lnum, kind, 0, 0, 0, rel, record_end_lnum - lnum, terminated)
        end
      end

      return extend_over_stale_lines(record_end_lnum)
    end,

    on_end = function(err)
      if err then
        on_end(err)
        return
      end

      -- Recalculate dirty columns
      columns:recalculate_dirty()
      store:maybe_compact()
      on_end()
    end,
  }, startlnum, endlnum, self._current_parse)
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

--- Get column count
---@return integer column_count
function CsvViewMetrics:column_count()
  return self._columns:count()
end

--- Get logical row count
---@return integer logical_row_count
function CsvViewMetrics:row_count_logical()
  if self.store.n > 0 then
    return self._mapper:physical_to_logical(self.store.n) or 0
  else
    return 0
  end
end

return CsvViewMetrics
