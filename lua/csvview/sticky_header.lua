local win_overlay = require("csvview.win_overlay")

local M = {}

M._sticky_header_wins = {} --- @type table<integer,integer> winid -> sticky-header winid

--- Sync the horizontal scroll of the sticky header window with the main window.
---@param winid integer csvview attached window
---@param header_winid integer sticky-header window
---@param header_lnum integer header line number
local function sync_horizontal_scroll(winid, header_winid, header_lnum)
  local win_view = vim.api.nvim_win_call(winid, vim.fn.winsaveview) ---@type vim.fn.winsaveview.ret
  vim.api.nvim_win_call(header_winid, function()
    local current = vim.fn.winsaveview()
    if current.leftcol ~= win_view.leftcol or current.lnum ~= header_lnum then
      vim.fn.winrestview({ topline = header_lnum, lnum = header_lnum, leftcol = win_view.leftcol })
    end
  end)
end

--- Get the border characters for the sticky header window.
---@param opts CsvView.InternalOptions
---@return (string| { [1]:string, [2]:string })[]?
local function get_sticky_header_border(opts)
  if not opts.view.sticky_header.separator then
    return nil
  end

  local separator = { opts.view.sticky_header.separator, "CsvViewStickyHeaderSeparator" }
  return { "", "", "", "", separator, separator, separator, "" }
end

--- Display sticky header.
---@param winid integer
---@param view CsvView.View
local function show_sticky_header(winid, view)
  -- Open sticky header window
  -- This is achieved by opening the original buffer in a 1-line size floating window.
  -- Initially, I tried to display it by overlaying virt_text on the first line, but I decided to use a floating window due to the following issues:
  --  - When smoothscroll is enabled, the header line, which should be fixed, appears to scroll.
  --  - Cannot overlay statuscolumn (line number, etc.).
  local win_width = vim.api.nvim_win_get_width(winid)
  local win_opts = { ---@type vim.api.keyset.win_config
    win = winid,
    relative = "win",
    width = win_width,
    height = 1,
    row = 0,
    col = 0,
    focusable = false,
    style = "minimal",
    border = get_sticky_header_border(view.opts),
  }

  -- Create window for sticky header, if not exists.
  local sticky_header_winid = M._sticky_header_wins[winid]
  if not sticky_header_winid or not vim.api.nvim_win_is_valid(sticky_header_winid) then
    win_opts.noautocmd = true
    sticky_header_winid = vim.api.nvim_open_win(view.bufnr, false, win_opts)
    M._sticky_header_wins[winid] = sticky_header_winid
  else
    vim.api.nvim_win_set_config(sticky_header_winid, win_opts)
    if vim.api.nvim_win_get_buf(sticky_header_winid) ~= view.bufnr then
      vim.api.nvim_win_set_buf(sticky_header_winid, view.bufnr)
    end
  end

  -- Mark as sticky header window
  vim.w[sticky_header_winid].csvview_sticky_header_win = true

  -- Set window options
  win_overlay.setup_overlay_win_options(sticky_header_winid, winid)
end

--- Determine if the sticky header should be shown.
---@param winid integer
---@param view CsvView.View
---@return boolean
local function should_show_sticky_header(winid, view)
  -- Do not show if the sticky_header option is disabled
  if not view.opts.view.sticky_header.enabled then
    return false
  end

  -- Do not show if the header line is not set
  local header_lnum = view.header_lnum
  if not header_lnum then
    return false
  end

  -- Do not show if the header line is visible in the window
  local top_lnum = vim.fn.line("w0", winid)
  if top_lnum <= header_lnum then
    return false
  end

  -- Hide if the cursor overlaps with the sticky header drawing position
  -- Also hide if it overlaps with the separator.
  local cur_lnum = vim.fn.line(".", winid)
  local header_bot_lnum = top_lnum + (view.opts.view.sticky_header.separator and 1 or 0)
  if cur_lnum <= header_bot_lnum then
    return false
  end

  return true
end

--- Close header window
---@param winid integer
function M.close_header_win_for(winid)
  local header_win = M._sticky_header_wins[winid]
  if not header_win then
    return
  end

  M._sticky_header_wins[winid] = nil
  if not vim.api.nvim_win_is_valid(header_win) then
    return
  end

  -- Close (use vim.schedule to avoid issues when called during BufUnload)
  vim.schedule(function()
    if vim.api.nvim_win_is_valid(header_win) then
      pcall(vim.api.nvim_win_close, header_win, true)
    end
  end)
end

--- statuscolumn function for the sticky header window.
---
--- Kept because it is referenced by name from the 'statuscolumn' expression, so a
--- user configuration may hold a copy of that string.
---@deprecated use `require("csvview.win_overlay").statuscolumn`
---@param winid integer csvview attached window
---@return string statuscolumn
function M.statuscolumn(winid)
  vim.deprecate("csvview.sticky_header.statuscolumn", "csvview.win_overlay.statuscolumn", "2.0.0", "csvview.nvim")
  return win_overlay.statuscolumn(winid)
end

--- Redraw all sticky headers
function M.redraw()
  local wins = vim.api.nvim_tabpage_list_wins(0)
  for _, winid in ipairs(wins) do
    local view = win_overlay.get_opened_csvview(winid)
    if view and should_show_sticky_header(winid, view) then
      show_sticky_header(winid, view)
      sync_horizontal_scroll(winid, M._sticky_header_wins[winid], view.header_lnum)
    else
      M.close_header_win_for(winid)
    end
  end
end

return M
