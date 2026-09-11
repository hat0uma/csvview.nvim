local M = {}

local util = require("csvview.util")

local CTRL_V = "\22" -- <C-v>

--- Neovim tracks multicursors as extmarks in this namespace.
--- See `:h multicursor`
local MCURSOR_NS = "nvim.multicursor"

--- @class CsvView.TextObject.Range
--- @field start_row integer 1-based line number of the start of the range
--- @field start_col integer 0-based byte offset of the start of the range
--- @field end_row integer 1-based line number of the end of the range
--- @field end_col integer 0-based byte offset of the end of the range (inclusive)

--- Check if the built-in multicursor feature is available. (Neovim 0.13+)
---@return boolean
local function has_multicursor()
  return vim.api.nvim_mcursor ~= nil
end

--- Check if a multicursor cascade is in progress.
---
--- While cascading, Neovim replays the text object at every cursor.
--- In that case new cursors must not be placed, the field under each cursor is just selected.
---@param bufnr integer
---@return boolean
local function is_cascading(bufnr)
  if vim.api.nvim__mcursor_cascading then
    return vim.api.nvim__mcursor_cascading()
  end

  -- Fallback for when the (private) API above is unavailable.
  -- Assume a cascade while the buffer has cursors, so that an ongoing session is never disturbed.
  local ns = vim.api.nvim_create_namespace(MCURSOR_NS)
  return #vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { limit = 1 }) > 0
end

--- Get the view of the buffer.
---@param bufnr integer
---@return CsvView.View? view, integer? winid
local function resolve_view(bufnr)
  local view = require("csvview.view").get(bufnr)
  if not view then
    vim.notify("csvview: not enabled for this buffer.")
    return nil, nil
  end

  -- Find the window in which this buffer is displayed
  local winid = util.buf_get_win(bufnr)
  if not winid then
    error("Could not find window for buffer " .. bufnr)
  end

  return view, winid
end

--- Exit visual mode and return the mode the text object was invoked from.
---@return string mode
local function exit_visual_mode()
  local mode = vim.fn.mode()
  if vim.tbl_contains({ "v", CTRL_V }, mode) then
    vim.cmd("normal! " .. mode)
  end
  return mode
end

--- Cancel the pending operator.
---
--- Without this, an operator applied to a text object that selects nothing operates on the
--- cursor position itself. e.g. `cif` on a comment line would start inserting there.
local function abort_operator()
  if vim.startswith(vim.fn.mode(1), "no") then
    -- "i" inserts the key before the rest of the typeahead, so that the operator is
    -- cancelled before the keys typed after it are processed.
    vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "ni", false)
  end
end

--- Get the range of the field at the given position.
---@param view CsvView.View
---@param lnum integer 1-based line number
---@param col_byte integer 0-based byte offset
---@param include_delimiter boolean
---@return CsvView.TextObject.Range? range nil if there is nothing to select
---@return integer? col_idx 1-based column index of the field
local function get_field_range(view, lnum, col_byte, include_delimiter)
  local row = view.metrics:row({ lnum = lnum })
  if not row or row.type == "comment" or row:field_count() == 0 then
    -- no selection if the row is a comment or empty
    return nil, nil
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

  -- Check if the field is valid.
  if field.start_row > field.end_row or (field.start_row == field.end_row and start_col > end_col) then
    return nil, nil
  end

  local range = { --- @type CsvView.TextObject.Range
    start_row = field.start_row,
    start_col = start_col,
    end_row = field.end_row,
    end_col = end_col,
  }
  return range, col_idx
end

--- Select the range with visual mode.
---@param range CsvView.TextObject.Range
---@param mode string mode the text object was invoked from
local function select_range(range, mode)
  vim.api.nvim_win_set_cursor(0, { range.start_row, range.start_col })
  vim.cmd("normal! " .. (mode == CTRL_V and CTRL_V or "v"))
  vim.api.nvim_win_set_cursor(0, { range.end_row, range.end_col })
end

--- Place a multicursor on the given column of every row except the row of the primary cursor.
---
--- Rows without the column, comment lines and empty lines are skipped.
---@param bufnr integer
---@param view CsvView.View
---@param col_idx integer 1-based column index
---@param cursor_lnum integer 1-based line number of the primary cursor
---@param include_header boolean whether to place a cursor on the header row
local function place_column_cursors(bufnr, view, col_idx, cursor_lnum, include_header)
  -- Drop the cursors of a previous session so that the text object always selects
  -- the column under the cursor.
  local ns = vim.api.nvim_create_namespace(MCURSOR_NS)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  -- The primary cursor already covers its own (logical) row.
  local cursor_row_lnum = view.metrics:get_logical_row_range(cursor_lnum)
  local skip_header_lnum = not include_header and view.header_lnum or nil

  for lnum = 1, view.metrics:row_count() do
    local row = view.metrics:row({ lnum = lnum })
    local skip = not row
      or row.type == "multiline_continuation" -- not the start of a logical row
      or lnum == cursor_row_lnum
      or lnum == skip_header_lnum
    if not skip then
      local field = view.metrics:get_logical_row_fields({ lnum = lnum })[col_idx]
      if field then
        vim.api.nvim_mcursor(bufnr, { field.start_row, field.start_col })
      end
    end
  end
end

--- Selects the current field.
--- @param bufnr integer?
--- @param opts? { include_delimiter?: boolean }
function M.field(bufnr, opts)
  bufnr = util.resolve_bufnr(bufnr)
  local view, winid = resolve_view(bufnr)
  if not view or not winid then
    return
  end

  opts = opts or {}
  local include_delimiter = opts.include_delimiter == nil and false or opts.include_delimiter

  -- Exit visual mode.
  local mode = exit_visual_mode()

  -- Get the (line, column) position of the cursor in the window
  local lnum, col_byte = unpack(vim.api.nvim_win_get_cursor(winid))

  local range = get_field_range(view, lnum, col_byte, include_delimiter)
  if not range then
    abort_operator()
    return
  end

  -- Select the field.
  select_range(range, mode)
end

--- Selects the current column.
---
--- This places a multicursor (`:h multicursor`) on the same column of every other row,
--- then selects the field under each cursor. A single operator therefore applies to the
--- whole column, e.g. `cic` rewrites every field of the column at once.
---
--- Requires Neovim 0.13 or later. On older versions only the field under the cursor is
--- selected, which makes this equivalent to `M.field()`.
---
--- NOTE: When invoked from visual mode, no cursor is placed and only the field under the
--- cursor is selected. Neovim replays a visual sequence as the keys that made it, and the
--- selection of this text object is made by a lua callback, which cannot be replayed.
--- Use an operator instead, e.g. `cic`, `dic`. (`yic` places the cursors without editing)
--- @param bufnr integer?
--- @param opts? { include_delimiter?: boolean, include_header?: boolean }
function M.column(bufnr, opts)
  bufnr = util.resolve_bufnr(bufnr)
  local view, winid = resolve_view(bufnr)
  if not view or not winid then
    return
  end

  opts = opts or {}
  local include_delimiter = opts.include_delimiter == nil and false or opts.include_delimiter
  local include_header = opts.include_header == nil and false or opts.include_header

  -- Exit visual mode.
  local mode = exit_visual_mode()

  -- Get the (line, column) position of the cursor in the window
  local lnum, col_byte = unpack(vim.api.nvim_win_get_cursor(winid))

  local range, col_idx = get_field_range(view, lnum, col_byte, include_delimiter)
  if not range or not col_idx then
    abort_operator()
    return
  end

  -- No cursor is placed when invoked from visual mode. See the note above.
  local from_visual = vim.tbl_contains({ "v", "V", CTRL_V }, mode)
  if not from_visual then
    if not has_multicursor() then
      vim.notify("csvview: the column text object requires Neovim 0.13 or later.", vim.log.levels.WARN)
    elseif not is_cascading(bufnr) then
      -- Neovim replays this text object at every cursor placed here,
      -- and each replay selects the field under its own cursor.
      place_column_cursors(bufnr, view, col_idx, lnum, include_header)
    end
  end

  -- Select the field of the primary cursor.
  select_range(range, mode)
end

return M
