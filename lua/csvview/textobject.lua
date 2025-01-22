local M = {}
local buf = require("csvview.buf")
local util = require("csvview.util")

--- Selects the current field.
--- @param bufnr integer?
--- @param opts? { include_delimiter?: boolean }
function M.field(bufnr, opts)
  bufnr = buf.resolve_bufnr(bufnr)
  local view = require("csvview.view").get(bufnr)
  if not view then
    vim.notify("csvview: not enabled for this buffer.")
    return
  end

  opts = opts or {}
  local include_delimiter = opts.include_delimiter == nil and false or opts.include_delimiter

  -- Exit visual mode.
  local mode = vim.fn.mode()
  if vim.tbl_contains({ "v", "" }, mode) then
    vim.cmd("normal! " .. mode)
  end

  -- Get the current cursor csv coordinates.
  local cursor = util.get_cursor(bufnr)
  local row_idx, col_idx = cursor.pos[1], cursor.pos[2]
  if not col_idx then -- empty line or comment
    return
  end

  -- Get the byte offset of the current field.
  local offset, field_len = view.metrics:col_idx_to_byte(row_idx, col_idx)
  local start_col = offset
  local end_col = offset + field_len - 1
  local is_last_col = col_idx == #view.metrics.rows[row_idx].fields
  if include_delimiter then
    if is_last_col then
      start_col = start_col - 1 -- include the before delimiter
    else
      end_col = end_col + 1 -- include the after delimiter
    end
  end

  if start_col > end_col then
    return
  end

  -- Select the field.
  vim.api.nvim_win_set_cursor(0, { row_idx, start_col })
  vim.cmd("normal! " .. (mode == "" and "" or "v"))
  vim.api.nvim_win_set_cursor(0, { row_idx, end_col })
end

return M
