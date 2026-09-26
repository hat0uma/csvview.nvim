-----------------------------------------------------------------------------
-- Row Mapper Module
-- Responsible for mapping between physical line numbers and logical row indices
-----------------------------------------------------------------------------
local KIND = require("csvview.metrics_store").KIND

--- @class CsvView.RowMapper
--- @field private _store CsvView.MetricsStore
local RowMapper = {}
RowMapper.__index = RowMapper

--- Create new RowMapper instance
---@param store CsvView.MetricsStore
---@return CsvView.RowMapper
function RowMapper:new(store)
  return setmetatable({ _store = store }, self)
end

--- Get logical row number from physical line number.
--- Comment lines count as logical rows.
---@param physical_lnum integer Physical line number (1-based)
---@return integer? logical_row_num Logical row number (1-based)
function RowMapper:physical_to_logical(physical_lnum)
  local store = self._store
  if not store:has_line(physical_lnum) then
    return nil -- Out of bounds
  end

  local kind = store.kind
  local logical_row_num = 0
  for i = 1, physical_lnum do
    if kind[i] ~= KIND.MULTILINE_CONTINUATION then
      logical_row_num = logical_row_num + 1
    end
  end
  return logical_row_num
end

--- Get the physical line number for a logical row number.
--- Comment lines count as logical rows.
---@param logical_row_num integer Logical row number (1-based)
---@return integer? physical_lnum Physical line number (1-based)
function RowMapper:logical_to_physical(logical_row_num)
  local store = self._store
  local kind = store.kind
  local logical_count = 0
  for i = 1, store.n do
    if kind[i] ~= KIND.MULTILINE_CONTINUATION then
      logical_count = logical_count + 1
      if logical_count == logical_row_num then
        return i
      end
    end
  end
  return nil -- Not found
end

--- Get the physical line number of a CSV row.
--- Unlike `logical_to_physical`, comment lines are not counted.
---@param row_idx integer 1-indexed CSV row index
---@return integer? lnum
function RowMapper:row_idx_to_lnum(row_idx)
  local store = self._store
  local kind = store.kind
  local count = 0
  for i = 1, store.n do
    local k = kind[i]
    if k == KIND.SINGLELINE or k == KIND.MULTILINE_START then
      count = count + 1
      if count == row_idx then
        return i
      end
    end
  end
  return nil -- Row not found
end

--- Find the start and end of the logical row containing the given physical line number
---@param lnum integer physical line number
---@return integer logical_start_lnum, integer logical_end_lnum
function RowMapper:get_logical_row_range(lnum)
  local store = self._store
  if not store:has_line(lnum) then
    error(string.format("Row out of bounds lnum=%d", lnum))
  end

  local start_lnum, end_lnum = lnum - store.rel[lnum], lnum + store.span[lnum]
  if not store:has_line(start_lnum) or not store:has_line(end_lnum) then
    error(string.format("Logical row out of bounds lnum=%d start=%d end=%d", lnum, start_lnum, end_lnum))
  end
  return start_lnum, end_lnum
end

--- @alias CsvView.Metrics.LogicalFieldRange { start_row: integer, start_col: integer, end_row: integer, end_col: integer }

--- Get field ranges for a logical row containing the given physical line number.
---@param lnum integer physical line number
---@return CsvView.Metrics.LogicalFieldRange[] ranges List of logical field ranges for the row
function RowMapper:get_logical_row_fields(lnum)
  local store = self._store
  if not store:has_line(lnum) then
    error(string.format("Row not found for lnum=%d", lnum))
  end

  local ranges = {} --- @type CsvView.Metrics.LogicalFieldRange[]
  if store.kind[lnum] == KIND.COMMENT then
    return ranges
  end

  local off, len = store.off, store.len
  local start_lnum, end_lnum = self:get_logical_row_range(lnum)
  for i = start_lnum, end_lnum do
    local base, col0 = store.base[i], store.col0[i]
    for j = 0, store.count[i] - 1 do
      local col_idx = col0 + j + 1
      local offset = off[base + j]
      local end_col = offset + len[base + j]
      local range = ranges[col_idx]
      if not range then
        ranges[col_idx] = { start_row = i, start_col = offset, end_row = i, end_col = end_col }
      else
        -- The field continues from the previous line
        range.end_row = i
        range.end_col = end_col
      end
    end
  end

  return ranges
end

--- Get the logical field range for a given line number and byte offset.
---@param lnum integer Line number (1-based)
---@param offset integer Byte offset within the line
---@return integer col_idx Column index of the field containing the byte offset
---@return CsvView.Metrics.LogicalFieldRange range Logical field range for the given line and offset
function RowMapper:get_logical_field_by_offset(lnum, offset)
  -- Convert the byte position to a column index
  local ranges = self:get_logical_row_fields(lnum)
  if #ranges == 0 then
    error(string.format("No fields found for lnum=%d", lnum))
  end

  local col_idx ---@type integer
  for i = 2, #ranges do
    if lnum < ranges[i].start_row then
      col_idx = i - 1
      break
    end
    if lnum == ranges[i].start_row and offset < ranges[i].start_col then
      -- If the line number is the same but the byte position is before the start of this range
      col_idx = i - 1
      break
    end
  end
  if not col_idx then
    col_idx = #ranges
  end

  return col_idx, ranges[col_idx]
end

return RowMapper
