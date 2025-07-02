local ffi = require("ffi")

local CsvViewMetricsRow = {}

--- @class CsvView.Metrics.Field: ffi.cdata*
--- @field offset integer
--- @field len integer
--- @field display_width integer
--- @field is_number boolean

--- @class CsvView.Metrics._RowStruct: ffi.cdata*
--- @field _type integer
--- @field _terminated integer
--- @field _end_loffset integer
--- @field _start_loffset integer
--- @field _skipped_ncol integer
--- @field _field_count integer
--- @field _fields userdata

ffi.cdef([[
  // define field structure
  typedef struct {
    int32_t offset;
    int32_t len;
    int32_t display_width;
    bool is_number;
  } csvview_field_t;

  // define row structure
  typedef struct {
    uint8_t _type;  // 0=comment, 1=singleline, 2=multiline_start, 3=multiline_continuation
    uint8_t _terminated;
    int32_t _end_loffset;
    int32_t _start_loffset;
    int32_t _skipped_ncol;
    uint32_t _field_count;
    csvview_field_t _fields[?];
  } csvview_row_t;
]])

local ROW_TYPE = {
  COMMENT = 0,
  SINGLELINE = 1,
  MULTILINE_START = 2,
  MULTILINE_CONTINUATION = 3,
}

--- @class CsvView.Metrics.CommentRow: CsvView.Metrics._RowStruct, CsvView.Metrics.RowPrototype
--- @field type "comment"

--- @class CsvView.Metrics.MultilineStartRow: CsvView.Metrics._RowStruct, CsvView.Metrics.RowPrototype
--- @field type "multiline_start"
--- @field end_loffset integer -- relative end line offset
--- @field terminated boolean -- whether the row is terminated, if false, parser reached lookahead limit

---
--- @class CsvView.Metrics.MultilineContinuationRow: CsvView.Metrics._RowStruct, CsvView.Metrics.RowPrototype
--- @field type "multiline_continuation"
---
--- example:
--- abc,def,"gh <--- type="multiline_start", end_loffset=4
--- i",jkl,"m   <--- type="multiline_continuation", start_loffset=1, skipped_ncol=2
--- n           <--- type="multiline_continuation", start_loffset=2, skipped_ncol=2
--- o           <--- type="multiline_continuation", start_loffset=3, skipped_ncol=4
--- p"          <--- type="multiline_continuation", start_loffset=4, skipped_ncol=4
--- @field start_loffset integer -- relative start line offset
--- @field end_loffset integer -- relative end line offset
--- @field skipped_ncol integer -- column number that was skipped in the continuation row
--- @field terminated boolean -- whether the row is terminated, if false, parser reached lookahead limit

--- @class CsvView.Metrics.SinglelineRow: CsvView.Metrics._RowStruct, CsvView.Metrics.RowPrototype
--- @field type "singleline"

--- @alias CsvView.Metrics.Row
--- | CsvView.Metrics.CommentRow
--- | CsvView.Metrics.MultilineStartRow
--- | CsvView.Metrics.MultilineContinuationRow
--- | CsvView.Metrics.SinglelineRow

--- @class CsvView.Metrics.RowPrototype
local prototype = {}

local mt = {
  --- __index metamethod for CsvView.Metrics.Row
  ---@param row CsvView.Metrics._RowStruct
  ---@param key string
  ---@return any
  __index = function(row, key)
    if key == "type" then
      return prototype.get_type(row)
    elseif key == "terminated" then
      return row._terminated == 1
    elseif key == "end_loffset" then
      if row._type == ROW_TYPE.MULTILINE_START or row._type == ROW_TYPE.MULTILINE_CONTINUATION then
        return row._end_loffset
      else
        error("end_loffset is only valid for multiline rows")
      end
    elseif key == "start_loffset" then
      if row._type == ROW_TYPE.MULTILINE_CONTINUATION then
        return row._start_loffset
      else
        error("start_loffset is only valid for multiline continuation rows")
      end
    elseif key == "skipped_ncol" then
      if row._type == ROW_TYPE.MULTILINE_CONTINUATION then
        return row._skipped_ncol
      else
        error("skipped_ncol is only valid for multiline continuation rows")
      end
    else
      return prototype[key]
    end
  end,
}

--- Get field by column index
---@param row CsvView.Metrics._RowStruct
---@param col_idx integer 1-indexed column index
---@return CsvView.Metrics.Field?
function prototype.field(row, col_idx)
  if row._type == ROW_TYPE.COMMENT then
    return nil
  end

  local idx ---@type integer
  if row._type == ROW_TYPE.MULTILINE_CONTINUATION then
    idx = col_idx - row._skipped_ncol - 1
  else
    idx = col_idx - 1
  end

  if idx < 0 or idx >= row._field_count then
    return nil
  end

  return row._fields[idx]
end

-- Get the number of fields in the row
---@param row CsvView.Metrics._RowStruct
---@return integer
function prototype.field_count(row)
  return row._field_count
end

--- Iterate over fields in the row
---@param row CsvView.Metrics._RowStruct
---@return fun(): integer?, CsvView.Metrics.Field?
function prototype.iter(row)
  local i = 0

  return function()
    if i >= row._field_count then
      return nil, nil
    end

    local field = row._fields[i] ---@type CsvView.Metrics.Field
    i = i + 1
    if row._type == ROW_TYPE.MULTILINE_CONTINUATION then
      return row._skipped_ncol + i, field
    else
      return i, field
    end
  end
end

-- Get the type of the row as a string
--- @param row CsvView.Metrics._RowStruct
---@return "comment" | "singleline" | "multiline_start" | "multiline_continuation"
function prototype.get_type(row)
  if row._type == ROW_TYPE.COMMENT then
    return "comment"
  elseif row._type == ROW_TYPE.MULTILINE_START then
    return "multiline_start"
  elseif row._type == ROW_TYPE.MULTILINE_CONTINUATION then
    return "multiline_continuation"
  else
    return "singleline"
  end
end

-----------------------------------------
-- Create a new row type
-----------------------------------------

local csvview_row_t = ffi.metatype("csvview_row_t", mt)

--- Create a new comment row
---@return CsvView.Metrics.CommentRow
function CsvViewMetricsRow.new_comment_row()
  ---@diagnostic disable-next-line: assign-type-mismatch
  local row = csvview_row_t(0) ---@type CsvView.Metrics.CommentRow
  row._type = ROW_TYPE.COMMENT
  row._field_count = 0
  return row
end

--- Create a new single line row
---@param fields CsvView.Metrics.Field[]
---@return CsvView.Metrics.SinglelineRow
function CsvViewMetricsRow.new_single_row(fields)
  local field_count = #fields

  ---@diagnostic disable-next-line: assign-type-mismatch
  local row = csvview_row_t(field_count) ---@type CsvView.Metrics.SinglelineRow
  row._type = ROW_TYPE.SINGLELINE

  row._field_count = field_count
  for i, field_info in ipairs(fields) do
    local field = row._fields[i - 1] ---@type CsvView.Metrics.Field
    field.offset = field_info.offset
    field.len = field_info.len
    field.display_width = field_info.display_width
    field.is_number = field_info.is_number
  end

  return row
end

--- Create a new multiline start row
---@param end_loffset integer
---@param terminated boolean
---@param fields CsvView.Metrics.Field[]
---@return CsvView.Metrics.MultilineStartRow
function CsvViewMetricsRow.new_multiline_start_row(end_loffset, terminated, fields)
  local field_count = #fields

  ---@diagnostic disable-next-line: assign-type-mismatch
  local row = csvview_row_t(field_count) ---@type CsvView.Metrics.MultilineStartRow
  row._type = ROW_TYPE.MULTILINE_START
  row._terminated = terminated and 1 or 0
  row._end_loffset = end_loffset

  row._field_count = field_count
  for i, field_info in ipairs(fields) do
    local field = row._fields[i - 1] ---@type CsvView.Metrics.Field
    field.offset = field_info.offset
    field.len = field_info.len
    field.display_width = field_info.display_width
    field.is_number = field_info.is_number
  end

  return row
end

--- Create a new multiline continuation row
---@param start_loffset integer
---@param end_loffset integer
---@param skipped_ncol integer
---@param terminated boolean
---@param fields CsvView.Metrics.Field[]
---@return CsvView.Metrics.MultilineContinuationRow
function CsvViewMetricsRow.new_multiline_continuation_row(start_loffset, end_loffset, skipped_ncol, terminated, fields)
  local field_count = #fields

  --- @diagnostic disable-next-line: assign-type-mismatch
  local row = csvview_row_t(field_count) ---@type CsvView.Metrics.MultilineContinuationRow
  row._type = ROW_TYPE.MULTILINE_CONTINUATION
  row._terminated = terminated and 1 or 0
  row._start_loffset = start_loffset
  row._end_loffset = end_loffset
  row._skipped_ncol = skipped_ncol

  row._field_count = field_count
  for i, field_info in ipairs(fields) do
    local field = row._fields[i - 1] ---@type CsvView.Metrics.Field
    field.offset = field_info.offset
    field.len = field_info.len
    field.display_width = field_info.display_width
    field.is_number = field_info.is_number
  end

  return row
end

return CsvViewMetricsRow
