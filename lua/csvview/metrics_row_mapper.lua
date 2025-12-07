-----------------------------------------------------------------------------
-- Row Mapper Module
-- Responsible for mapping between physical line numbers and logical row indices
-----------------------------------------------------------------------------

--- @class CsvView.RowMapper
--- @field private _get_row fun(lnum: integer): CsvView.Metrics.Row? function to get row by physical line number
--- @field private _row_count fun(): integer function to get total row count
local RowMapper = {}

--- Create new RowMapper instance
---@param get_row fun(lnum: integer): CsvView.Metrics.Row? function to get row by physical line number
---@param row_count fun(): integer function to get total row count
---@return CsvView.RowMapper
function RowMapper:new(get_row, row_count)
  self.__index = self
  local obj = {
    _get_row = get_row,
    _row_count = row_count,
  }
  return setmetatable(obj, self)
end

--- Get row by physical line number
---@param lnum integer 1-indexed physical line number
---@return CsvView.Metrics.Row?
function RowMapper:_row(lnum)
  return self._get_row(lnum)
end

--- Check if row type is a logical row start
---@param row_type string
---@return boolean
local function is_logical_row_start(row_type)
  return row_type == "singleline" or row_type == "multiline_start" or row_type == "comment"
end

--- Get logical row number from physical line number
---@param physical_lnum integer Physical line number (1-based)
---@return integer? logical_row_num Logical row number (1-based)
function RowMapper:physical_to_logical(physical_lnum)
  local logical_row_num = 0

  for i = 1, physical_lnum do
    local row = self:_row(i)
    if not row then
      return nil -- Out of bounds
    end

    -- Count only the start of logical rows
    if is_logical_row_start(row.type) then
      logical_row_num = logical_row_num + 1
    end
  end

  return logical_row_num
end

--- Get the physical line number for a logical row number
---@param logical_row_num integer Logical row number (1-based)
---@return integer? physical_lnum Physical line number (1-based)
function RowMapper:logical_to_physical(logical_row_num)
  local logical_count = 0
  local total_rows = self._row_count()

  for i = 1, total_rows do
    local row = self:_row(i)
    if not row then
      return nil
    end

    -- Count only the start of logical rows
    if is_logical_row_start(row.type) then
      logical_count = logical_count + 1
      if logical_count == logical_row_num then
        return i
      end
    end
  end

  return nil -- Not found
end

--- Get row by logical row index (1-indexed)
---@param row_idx integer 1-indexed CSV row index
---@return CsvView.Metrics.Row?
function RowMapper:get_row_by_row_idx(row_idx)
  local logical_row_count = 0
  local total_rows = self._row_count()

  for i = 1, total_rows do
    local row = self:_row(i)
    if not row then
      return nil
    end

    -- Count only the start of logical rows
    if row.type == "singleline" or row.type == "multiline_start" then
      logical_row_count = logical_row_count + 1
      if logical_row_count == row_idx then
        return row
      end
    end
  end

  return nil -- Row not found
end

--- Find the start and end of the logical row containing the given physical line number
---@param lnum integer physical line number
---@return integer logical_start_lnum, integer logical_end_lnum
function RowMapper:get_logical_row_range(lnum)
  local row = self:_row(lnum)
  if not row then
    error(string.format("Row out of bounds lnum=%d", lnum))
  end

  if row.type == "multiline_continuation" then
    local start_lnum = lnum - row.start_loffset
    local start_row = self:_row(start_lnum)
    if not start_row then
      error(string.format("Start row not found for lnum=%d", lnum))
    end
    local endlnum = start_lnum + start_row.end_loffset
    return start_lnum, endlnum
  elseif row.type == "multiline_start" then
    return lnum, lnum + row.end_loffset
  else
    return lnum, lnum
  end
end

--- @alias CsvView.Metrics.LogicalFieldRange { start_row: integer, start_col: integer, end_row: integer, end_col: integer }

--- Get field ranges for a logical row containing the given physical line number.
---@param lnum integer physical line number
---@return CsvView.Metrics.LogicalFieldRange[] ranges List of logical field ranges for the row
function RowMapper:get_logical_row_fields(lnum)
  local row = self:_row(lnum)
  if not row then
    error(string.format("Row not found for lnum=%d", lnum))
  end

  local ranges = {} --- @type CsvView.Metrics.LogicalFieldRange[]

  -- Handle comment or empty rows
  if row.type == "comment" or row:field_count() == 0 then
    return ranges
  end

  if row.type == "singleline" then
    for _, field in row:iter() do
      local start_col = field.offset
      local range = { --- @type CsvView.Metrics.LogicalFieldRange
        start_row = lnum,
        start_col = start_col,
        end_row = lnum,
        end_col = math.max(field.offset + field.len, start_col),
      }
      table.insert(ranges, range)
    end
    return ranges
  end

  -- Handle multi-line rows
  local logical_start_lnum, logical_end_lnum = self:get_logical_row_range(lnum)
  for i = logical_start_lnum, logical_end_lnum do
    local logical_row = self:_row(i)
    if not logical_row then
      error(string.format("Logical row not found for lnum=%d", i))
    end

    for col_idx, field in logical_row:iter() do
      if not ranges[col_idx] then
        ranges[col_idx] = { --- @type CsvView.Metrics.LogicalFieldRange
          start_row = i,
          start_col = field.offset,
          end_row = i,
          end_col = field.offset + field.len,
        }
      else
        -- Extend the end row and column if this field continues on the same logical row
        ranges[col_idx].end_row = i
        ranges[col_idx].end_col = field.offset + field.len
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
