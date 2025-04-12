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

  -- Get the field range.
  local row = view.metrics.rows[row_idx]
  local field = row.fields[col_idx]
  local start_col = field.offset
  local end_col = field.offset + field.len - 1

  -- If `include_delimiter` is true, expand the range.
  -- NOTE: If the number of fields is 1, there is no delimiter. Ignore `include_delimiter`.
  if include_delimiter and #row.fields > 1 then
    local is_last_col = col_idx == #view.metrics.rows[row_idx].fields
    if is_last_col then
      local prev_field = row.fields[col_idx - 1]
      start_col = prev_field.offset + prev_field.len -- include the before delimiter
    else
      local next_field = row.fields[col_idx + 1]
      end_col = next_field.offset - 1 -- include the after delimiter
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
