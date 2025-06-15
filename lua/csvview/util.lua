--- Utility functions for CSVView.
local M = {}

local buf = require("csvview.buf")

-- TODO move this to CsvView.Metrics
--- @alias CsvView.Metrics.LogicalFieldRange { start_row: integer, start_col: integer, end_row: integer, end_col: integer }

-- TODO move this to CsvView.Metrics
--- Get logical field ranges for a given row.
---@param metrics CsvView.Metrics Metrics object for the CSV buffer
---@param lnum integer Line number (1-based)
---@return CsvView.Metrics.LogicalFieldRange[] ranges List of logical field ranges for the row
function M._get_logical_field_ranges(metrics, lnum)
  local row = metrics:row({ lnum = lnum })
  local ranges = {} --- @type CsvView.Metrics.LogicalFieldRange[]

  -- Handle comment or empty rows
  if row.type == "comment" or row:field_count() == 0 then
    return ranges
  end

  if row.type == "singleline" then
    for _, field in row:iter() do
      local range = { --- @type CsvView.Metrics.LogicalFieldRange
        start_row = lnum,
        start_col = field.offset,
        end_row = lnum,
        end_col = field.offset + field.len - 1,
      }
      table.insert(ranges, range)
    end
    return ranges
  end

  local logical_start_lnum, logical_end_lnum = metrics:find_logical_row_range(lnum)
  for i = logical_start_lnum, logical_end_lnum do
    local logical_row = metrics:row({ lnum = i })
    for col_idx, field in logical_row:iter() do
      if not ranges[col_idx] then
        ranges[col_idx] = { --- @type CsvView.Metrics.LogicalFieldRange
          start_row = i,
          start_col = field.offset,
          end_row = i,
          end_col = field.offset + field.len - 1,
        }
      else
        -- Extend the end row and column if this field continues on the same logical row
        ranges[col_idx].end_row = i
        ranges[col_idx].end_col = field.offset + field.len - 1
      end
    end
  end

  return ranges
end

-- TODO move this to CsvView.Metrics
--- Get the logical field range for a given line number and byte offset.
---@param metrics CsvView.Metrics Metrics object for the CSV buffer
---@param lnum integer Line number (1-based)
---@param offset integer Byte offset within the line
---@return integer col_idx Column index of the field containing the byte offset
---@return CsvView.Metrics.LogicalFieldRange range Logical field range for the given line and offset
function M._get_logical_field_by_offet(metrics, lnum, offset)
  -- Convert the byte position to a column index
  local ranges = M._get_logical_field_ranges(metrics, lnum)
  local col_idx ---@type integer
  for i = 2, #ranges do
    if lnum < ranges[i].start_row then
      -- If the line number is before the start of this range, we can stop
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
    -- If we didn't find a range, it means the cursor is in the last field
    col_idx = #ranges
  end

  return col_idx, ranges[col_idx]
end

---@class CsvView.Cursor
---@field kind "field" | "comment" | "empty_line" Cursor kind
---@field pos [integer,integer?] 1-based [row, col] csv coordinates
---@field anchor? CsvView.CursorAnchor
---@field text? string

--- Cursor anchor states within a CSV field.
--- - `"start"`: Cursor is at the beginning of the field.
--- - `"end"`: Cursor is at the end of the field.
--- - `"delimiter"`: Cursor is at the delimiter after the field.
--- - `"inside"`: Cursor is inside the field.
---@alias CsvView.CursorAnchor "start" | "end" | "delimiter" | "inside"

---Get cursor information for the current position in the buffer.
---It checks whether the current line is a comment or a valid CSV row,
---and returns cursor information including CSV row/column and an "anchor" state.
---@param bufnr? integer Optional buffer number. Defaults to the current buffer if not provided.
---@return CsvView.Cursor cursor Cursor information
function M.get_cursor(bufnr)
  bufnr = buf.resolve_bufnr(bufnr)

  -- Get the corresponding view for this buffer
  local view = require("csvview.view").get(bufnr)
  if not view then
    error("CsvView is not enabled for this buffer.")
  end

  -- Find the window in which this buffer is displayed
  local winid = buf.get_win(bufnr)
  if not winid then
    error("Could not find window for buffer " .. bufnr)
  end

  -- Get the (line, column) position of the cursor in the window
  local lnum, col_byte = unpack(vim.api.nvim_win_get_cursor(winid))
  local row = view.metrics:row({ lnum = lnum })
  if not row then
    error("Cursor is out of bounds.")
  end

  -- If this line is marked as a comment, return a CommentCursor
  if row.type == "comment" then
    return { kind = "comment", pos = { lnum } }
  end

  -- Empty line
  if row:field_count() == 0 then
    return { kind = "empty_line", pos = { lnum } }
  end

  local col_idx, range = M._get_logical_field_by_offet(view.metrics, lnum, col_byte)
  local lines = vim.api.nvim_buf_get_text(
    bufnr,
    range.start_row - 1, -- Convert to 0-based index
    range.start_col,
    range.end_row - 1, -- Convert to 0-based index
    range.end_col + 1,
    {}
  )
  local text = table.concat(lines, "\n") -- Join lines if multiline

  -- Determine the anchor state of the cursor within this field
  ---@type CsvView.CursorAnchor
  local anchor
  if lnum == range.end_row and col_byte > range.end_col then
    anchor = "delimiter"
  elseif lnum == range.start_row and col_byte == range.start_col then
    anchor = "start"
  elseif lnum == range.end_row then
    local offset_in_field = lnum == range.start_row and col_byte - range.start_col or col_byte
    -- Use `vim.fn.charidx()` to handle multibyte safety in indexing.
    local charlen = vim.fn.charidx(lines[#lines], #lines[#lines])
    local charidx = vim.fn.charidx(lines[#lines], offset_in_field)
    anchor = charidx == charlen - 1 and "end" or "inside"
  else
    anchor = "inside"
  end

  return { --- @type CsvView.Cursor
    kind = "field",
    -- TODO: use logical row instead of lnum for multiline fields
    pos = { lnum, col_idx },
    anchor = anchor,
    text = text,
  }
end

return M
