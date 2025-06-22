local nop = function() end

-----------------------------------------------------------------------------
-- Row types
-----------------------------------------------------------------------------

--- @class CsvView.Metrics.CommentRow
--- @field type "comment"
local CommentRow = {}
CommentRow.__index = CommentRow

--- @class CsvView.Metrics.MultilineStartRow
--- @field type "multiline_start"
--- @field _fields CsvView.Metrics.Field[]
--- @field end_loffset integer -- relative end line offset
--- @field terminated boolean -- whether the row is terminated, if false, parser reached lookahead limit
local MultilineStartRow = {}
MultilineStartRow.__index = MultilineStartRow

---
--- @class CsvView.Metrics.MultilineContinuationRow
--- @field type "multiline_continuation"
---
---
--- @field _fields CsvView.Metrics.Field[]
---
--- example:
--- abc,def,"gh <--- type="multiline_start", end_loffset=4
--- i",jkl,"m   <--- type="multiline_continuation", start_loffset=1, start_field_offset=1, skipped_ncol=2
--- n           <--- type="multiline_continuation", start_loffset=2, start_field_offset=1, skipped_ncol=2
--- o           <--- type="multiline_continuation", start_loffset=3, start_field_offset=2, skipped_ncol=4
--- p"          <--- type="multiline_continuation", start_loffset=4, start_field_offset=3, skipped_ncol=4
--- @field start_loffset integer -- relative start line offset
--- @field end_loffset integer -- relative end line offset
--- @field start_field_offset integer -- relative start field offset
--- @field skipped_ncol integer -- column number that was skipped in the continuation row
--- @field terminated boolean -- whether the row is terminated, if false, parser reached lookahead limit
local MultilineContinuationRow = {}
MultilineContinuationRow.__index = MultilineContinuationRow

--- @class CsvView.Metrics.SinglelineRow
--- @field type "singleline"
--- @field _fields CsvView.Metrics.Field[] -- empty for comment rows
local SinglelineRow = {}
SinglelineRow.__index = SinglelineRow

--- @alias CsvView.Metrics.Row
--- | CsvView.Metrics.CommentRow
--- | CsvView.Metrics.MultilineStartRow
--- | CsvView.Metrics.MultilineContinuationRow
--- | CsvView.Metrics.SinglelineRow

-----------------------------------------------------------------------------
-- Metrics class
-----------------------------------------------------------------------------
--- Get field by byte offset
--- @class CsvView.Metrics
--- @field private _rows CsvView.Metrics.Row[]
--- @field private _columns CsvView.Metrics.Column[]
--- @field private _bufnr integer
--- @field private _opts CsvView.InternalOptions
--- @field private _parser CsvView.Parser
--- @field private _current_parse { cancelled: boolean }?
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
---@return CsvView.Metrics.Row?
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
---@return CsvView.Metrics.Column?
function CsvViewMetrics:column(col_idx)
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

  if self._current_parse then
    self._current_parse.cancelled = true
  end
  self._current_parse = { cancelled = false }

  -- Get the range of affected lines
  local start_reparse, end_reparse = self:_calculate_reparse_range(first, prev_last, last)

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
  self:_compute_metrics(start_reparse, end_reparse, recalculate_columns, on_end)
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
    local field_start_lnum, field_end_lnum = self:get_logical_row_range(first + 1)
    start_reparse = field_start_lnum
    end_reparse = math.max(field_end_lnum, last)
  elseif first ~= 0 and first <= #self._rows then
    -- if adding a new row at the end of the last row
    local field_start_lnum, field_end_lnum = self:get_logical_row_range(first)
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
  end_reparse = math.min(end_reparse + row_delta, vim.api.nvim_buf_line_count(self._bufnr))

  return start_reparse, end_reparse
end

--- Get row metrics by line number
---@param lnum integer 1-indexed line number
---@return CsvView.Metrics.Row?
function CsvViewMetrics:_get_row_by_lnum(lnum)
  return self._rows[lnum]
end

--- Get row metrics by CSV row index
---@param row_idx integer 1-indexed CSV row index
---@return CsvView.Metrics.Row?
function CsvViewMetrics:_get_row_by_row_idx(row_idx)
  local logical_row_count = 0

  for i = 1, #self._rows do
    local row = self._rows[i]

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

--- Compute row metrics
---@param lnum integer line number
---@param is_comment boolean
---@param parsed_fields CsvView.Parser.FieldInfo[]
---@param parsed_endlnum integer end line number of the parsed row
---@param terminated boolean whether the row is terminated, if false, parser reached lookahead limit
---@return CsvView.Metrics.Row[]
local function construct_rows(lnum, is_comment, parsed_fields, parsed_endlnum, terminated)
  if is_comment then
    return { CommentRow:new() }
  end

  if parsed_endlnum == lnum then -- Single line row
    local row = SinglelineRow:new({})
    for _, field in ipairs(parsed_fields) do
      local field_text = field.text
      assert(type(field_text) == "string")

      local width = vim.fn.strdisplaywidth(field_text)
      row:append({
        offset = field.start_pos - 1,
        len = #field.text,
        display_width = width,
        is_number = tonumber(field.text) ~= nil,
      })
    end
    return { row }
  end

  -- Multi-line row
  local start_row = MultilineStartRow:new({}, parsed_endlnum - lnum, terminated)
  local index = 1
  local rows = { start_row } --- @type CsvView.Metrics.Row[]
  for field_index, field in ipairs(parsed_fields) do
    local field_text = field.text

    if type(field_text) == "table" then
      -- Multi-line field
      local field_start_lnum = index
      for i, text in ipairs(field_text) do
        -- first line starts at field.start_pos, others are 0
        local offset = i == 1 and field.start_pos - 1 or 0
        local width = vim.fn.strdisplaywidth(text)
        rows[index]:append({ offset = offset, len = #text, display_width = width, is_number = false })

        -- Add next row
        if i ~= #field_text then
          index = index + 1
          rows[index] = MultilineContinuationRow:new(
            {},
            index - 1, -- relative start line offset
            parsed_endlnum - lnum - index + 1, -- relative end line offset
            index - field_start_lnum, -- relative start field offset
            field_index - 1,
            terminated
          )
        end
      end
    else
      -- Single-line field
      rows[index]:append({
        offset = field.start_pos - 1,
        len = #field.text,
        display_width = vim.fn.strdisplaywidth(field_text),
        is_number = tonumber(field.text) ~= nil,
      })
    end
  end
  return rows
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
    on_line = function(lnum, is_comment, fields, parsed_endlnum, terminated)
      local new_endlnum = nil ---@type integer?
      local rows = construct_rows(lnum, is_comment, fields, parsed_endlnum, terminated)
      assert(#rows == parsed_endlnum - lnum + 1, "Invalid number of rows computed")

      -- Update row metrics and adjust column metrics
      for i, row in ipairs(rows) do
        local line = lnum + i - 1
        local prev_row = self._rows[line]
        self._rows[line] = row

        if prev_row and prev_row.type == "multiline_start" and row.type == "multiline_continuation" then
          -- If the structure of the multi-line field is broken, it affects all subsequent rows,
          -- so all rows need to be recalculated.
          new_endlnum = vim.api.nvim_buf_line_count(self._bufnr) - 1
        end

        self:_mark_recalculation_on_decrease_fields(line, prev_row, recalculate_columns)
        self:_adjust_column_metrics_for_row(line, recalculate_columns)
      end
      return new_endlnum
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
  }, startlnum, endlnum, self._current_parse)
end

--- Recalculate column metrics for the specified column
---@param col_idx integer
function CsvViewMetrics:_recalculate_column(col_idx)
  local max_width = 0
  local max_row = nil

  -- Find the maximum width in the column
  for row_idx, row in ipairs(self._rows) do
    if row.type ~= "comment" then
      local field = row:field(col_idx)
      if field and field.display_width > max_width then
        max_width = field.display_width
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

  for col_idx, _ in prev_row:iter() do
    -- Check if the column exists and if the current row was the maximum width row for this column.
    if self._columns[col_idx] and self._columns[col_idx].max_row == row_idx then
      local current_field = row:field(col_idx)
      if not current_field then
        recalculate_columns[col_idx] = true
      end
    end
  end
end

--- Adjust column metrics for the specified row
---@param row_idx integer row index
---@param recalculate_columns table<integer,boolean> recalculate columns
function CsvViewMetrics:_adjust_column_metrics_for_row(row_idx, recalculate_columns)
  local row = self._rows[row_idx]

  -- Update column metrics
  for col_idx, field in row:iter() do
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
    self._rows[i] = SinglelineRow:new({})
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
  local row = self._rows[lnum]
  if not row then
    error(string.format("Row out of bounds lnum=%d", lnum))
  end

  if row.type == "multiline_continuation" then
    local start_lnum = lnum - row.start_loffset
    local endlnum = start_lnum + self._rows[start_lnum].end_loffset
    return start_lnum, endlnum
  elseif row.type == "multiline_start" then
    return lnum, lnum + row.end_loffset
  else
    return lnum, lnum
  end
end

--- Get logical row number from physical line number
---@param physical_lnum integer Physical line number (1-based)
---@return integer? logical_row_num Logical row number (1-based)
function CsvViewMetrics:get_logical_row_idx(physical_lnum)
  local logical_row_num = 0

  for i = 1, physical_lnum do
    local row = self._rows[i]
    if not row then
      return nil -- Out of bounds
    end

    -- Count only the start of logical rows
    if row.type == "singleline" or row.type == "multiline_start" or row.type == "comment" then
      logical_row_num = logical_row_num + 1
    end
  end

  return logical_row_num
end

--- Get the physical line number for a logical row number
---@param logical_row_num integer Logical row number (1-based)
---@return integer? physical_lnum Physical line number (1-based)
function CsvViewMetrics:get_physical_line_number(logical_row_num)
  local logical_count = 0

  for i = 1, #self._rows do
    local row = self._rows[i]

    -- Count only the start of logical rows
    if row.type == "singleline" or row.type == "multiline_start" or row.type == "comment" then
      logical_count = logical_count + 1
      if logical_count == logical_row_num then
        return i
      end
    end
  end

  return nil -- Not found
end

--- @alias CsvView.Metrics.LogicalFieldRange { start_row: integer, start_col: integer, end_row: integer, end_col: integer }

--- Get field ranges for a logical row containing the given physical line number.
---@param opts { lnum?: integer, row_idx?:integer } specify either `lnum` or `row_idx`
---@return CsvView.Metrics.LogicalFieldRange[] ranges List of logical field ranges for the row
function CsvViewMetrics:get_logical_row_fields(opts)
  local lnum = opts.lnum or self:get_physical_line_number(opts.row_idx)
  if not lnum then
    error(string.format("Invalid lnum or row_idx: lnum=%s, row_idx=%s", opts.lnum, opts.row_idx))
  end

  local row = self:row({ lnum = lnum })
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
    local logical_row = assert(self:row({ lnum = i }))
    for col_idx, field in logical_row:iter() do
      if not ranges[col_idx] then
        local start_col = field.offset
        ranges[col_idx] = { --- @type CsvView.Metrics.LogicalFieldRange
          start_row = i,
          start_col = start_col,
          end_row = i,
          end_col = math.max(field.offset + field.len, start_col),
        }
      else
        -- Extend the end row and column if this field continues on the same logical row
        ranges[col_idx].end_row = i
        ranges[col_idx].end_col = math.max(field.offset + field.len, ranges[col_idx].start_col)
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
function CsvViewMetrics:get_logical_field_by_offet(lnum, offset)
  -- Convert the byte position to a column index
  local ranges = self:get_logical_row_fields({ lnum = lnum })
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

----------------------------------------------------
-- Row functions
----------------------------------------------------

--- Iterate over fields in the row
---@param row CsvView.Metrics.Row
---@return fun():integer?,CsvView.Metrics.Field?
local function iter(row)
  local i = 0
  return function()
    if not row._fields then
      return nil, nil
    end

    i = i + 1
    if i > #row._fields then
      return nil, nil
    end

    if row.type == "multiline_continuation" then
      return row.skipped_ncol + i, row._fields[i]
    else
      return i, row._fields[i]
    end
  end
end

--- Iterate over fields in the row
---@param row CsvView.Metrics.Row
---@param field CsvView.Metrics.Field
local function append(row, field)
  table.insert(row._fields, field)
end

--- Get field by column index
--- @param row CsvView.Metrics.Row
--- @param col_idx integer 1-indexed column index
--- @return CsvView.Metrics.Field?
local function field(row, col_idx)
  if row.type == "comment" then
    return nil
  end

  if row.type == "multiline_continuation" then
    col_idx = col_idx - row.skipped_ncol
  end
  return row._fields[col_idx]
end

--- Get the number of fields in the row
--- @param row CsvView.Metrics.Row
--- @return integer
local function field_count(row)
  return #row._fields
end

--- Create a new CommentRow instance
--- @return CsvView.Metrics.CommentRow
function CommentRow:new()
  local obj = {}
  obj.type = "comment"
  return setmetatable(obj, self)
end
CommentRow.iter = iter
CommentRow.append = append
CommentRow.field = field
CommentRow.field_count = field_count

--- Create a new SinglelineRow instance
---@param fields CsvView.Metrics.Field[] fields in the row
---@return CsvView.Metrics.SinglelineRow
function SinglelineRow:new(fields)
  local obj = {}
  obj.type = "singleline"
  obj._fields = fields
  return setmetatable(obj, self)
end
SinglelineRow.iter = iter
SinglelineRow.append = append
SinglelineRow.field = field
SinglelineRow.field_count = field_count

--- Create a new MultilineStartRow instance
--- @param fields CsvView.Metrics.Field[] fields in the row
--- @param end_loffset integer relative end line offset
--- @param terminated boolean whether the row is terminated, if false, parser reached lookahead limit
--- @return CsvView.Metrics.MultilineStartRow
function MultilineStartRow:new(fields, end_loffset, terminated)
  local obj = {}
  obj.type = "multiline_start"
  obj._fields = fields or {}
  obj.end_loffset = end_loffset
  obj.terminated = terminated

  return setmetatable(obj, self)
end
MultilineStartRow.iter = iter
MultilineStartRow.append = append
MultilineStartRow.field = field
MultilineStartRow.field_count = field_count

--- Create a new MultilineContinuationRow instance
--- @param fields CsvView.Metrics.Field[] fields in the row
--- @param start_loffset integer relative start line offset
--- @param end_loffset integer relative end line offset
--- @param start_field_offset integer relative start field offset
--- @param skipped_ncol integer column number that was skipped in the continuation row
--- @param terminated boolean whether the row is terminated, if false, parser reached lookahead limit
--- @return CsvView.Metrics.MultilineContinuationRow
function MultilineContinuationRow:new(fields, start_loffset, end_loffset, start_field_offset, skipped_ncol, terminated)
  local obj = {}
  obj.type = "multiline_continuation"
  obj._fields = fields
  obj.start_loffset = start_loffset
  obj.end_loffset = end_loffset
  obj.start_field_offset = start_field_offset
  obj.skipped_ncol = skipped_ncol
  obj.terminated = terminated
  return setmetatable(obj, self)
end
MultilineContinuationRow.iter = iter
MultilineContinuationRow.append = append
MultilineContinuationRow.field = field
MultilineContinuationRow.field_count = field_count

return CsvViewMetrics
