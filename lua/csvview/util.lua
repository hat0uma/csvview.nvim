--- Utility functions for CSVView.
local M = {}

local buf = require("csvview.buf")

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

  local col_idx, range = view.metrics:get_logical_field_by_offet(lnum, col_byte)
  local lines = vim.api.nvim_buf_get_text(
    bufnr,
    range.start_row - 1, -- Convert to 0-based index
    range.start_col,
    range.end_row - 1, -- Convert to 0-based index
    range.end_col,
    {}
  )
  local text = table.concat(lines, "\n") -- Join lines if multiline

  -- Determine the anchor state of the cursor within this field
  ---@type CsvView.CursorAnchor
  local anchor
  if lnum == range.end_row and col_byte >= range.end_col then
    anchor = "delimiter"
  elseif lnum == range.start_row and col_byte == range.start_col then
    anchor = "start"
  elseif lnum == range.end_row then
    local last_line = lines[#lines]
    local offset_in_field = lnum == range.start_row and col_byte - range.start_col or col_byte
    -- Use `vim.fn.charidx()` to handle multibyte safety in indexing.
    local charlen = vim.fn.charidx(last_line, #last_line)
    local charidx = vim.fn.charidx(last_line, offset_in_field)
    anchor = charidx == charlen - 1 and "end" or "inside"
  else
    anchor = "inside"
  end

  local logical_row_number = view.metrics:get_logical_row_idx(lnum)
  return { --- @type CsvView.Cursor
    kind = "field",
    pos = { logical_row_number, col_idx },
    anchor = anchor,
    text = text,
  }
end

return M
