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
  local row = view.metrics.rows[lnum]
  if not row then
    error("Cursor is out of bounds.")
  end

  -- If this line is marked as a comment, return a CommentCursor
  if row.is_comment then
    return { kind = "comment", pos = { lnum } }
  end

  -- Empty line
  if #row.fields == 0 then
    return { kind = "empty_line", pos = { lnum } }
  end

  -- Convert the byte position to a column index
  local col_idx, offset = view.metrics:byte_to_col_idx(lnum, col_byte)

  local field = row.fields[col_idx]
  local offset_in_field = col_byte - offset
  local text = vim.api.nvim_buf_get_text(bufnr, lnum - 1, offset, lnum - 1, offset + field.len, {})[1]

  -- Determine the anchor state of the cursor within this field
  ---@type CsvView.CursorAnchor
  local anchor
  if offset_in_field >= field.len then
    anchor = "delimiter"
  elseif offset_in_field == 0 then
    anchor = "start"
  else
    -- Use `vim.fn.charidx()` to handle multibyte safety in indexing.
    local charlen = vim.fn.charidx(text, field.len)
    local charidx = vim.fn.charidx(text, offset_in_field)
    anchor = charidx == charlen - 1 and "end" or "inside"
  end

  return { --- @type CsvView.Cursor
    kind = "field",
    pos = { lnum, col_idx },
    anchor = anchor,
    text = text,
  }
end

return M
