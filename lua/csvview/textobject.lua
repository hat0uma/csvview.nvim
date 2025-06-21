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

  -- Find the window in which this buffer is displayed
  local winid = buf.get_win(bufnr)
  if not winid then
    error("Could not find window for buffer " .. bufnr)
  end

  -- Exit visual mode.
  local mode = vim.fn.mode()
  if vim.tbl_contains({ "v", "" }, mode) then
    vim.cmd("normal! " .. mode)
  end

  -- Get the (line, column) position of the cursor in the window
  local lnum, col_byte = unpack(vim.api.nvim_win_get_cursor(winid))

  local row = view.metrics:row({ lnum = lnum })
  if not row or row.type == "comment" or row:field_count() == 0 then
    -- no selection if the row is a comment or empty
    return
  end

  local col_idx, field = view.metrics:get_logical_field_by_offet(lnum, col_byte)
  local fields = view.metrics:get_logical_row_fields({ lnum = lnum })

  -- Get the field range.
  local start_col = field.start_col
  local end_col = field.end_col - 1

  -- If `include_delimiter` is true, expand the range.
  -- NOTE: If the number of fields is 1, there is no delimiter. Ignore `include_delimiter`.
  if include_delimiter and #fields > 1 then
    local is_last_col = col_idx == #fields
    if is_last_col then
      local prev_field = fields[col_idx - 1]
      start_col = prev_field.end_col -- include the before delimiter
    else
      local next_field = fields[col_idx + 1]
      end_col = next_field.start_col - 1 -- include the after delimiter
    end
  end

  if start_col > end_col then
    return
  end

  -- Select the field.
  vim.api.nvim_win_set_cursor(0, { field.start_row, start_col })
  vim.cmd("normal! " .. (mode == "" and "" or "v"))
  vim.api.nvim_win_set_cursor(0, { field.end_row, end_col })
end

return M
