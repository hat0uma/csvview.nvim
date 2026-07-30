local win_overlay = require("csvview.win_overlay")

local M = {}

M._sticky_columns_wins = {} --- @type table<integer,integer> winid -> sticky-columns winid
M._corner_wins = {} --- @type table<integer,integer> winid -> pinned-header-corner winid
M._saved_sidescrolloff = {} --- @type table<integer,integer> winid -> 'sidescrolloff' before pinning

--- Width of the gutter (number column, signs, folds) of a window.
---@param winid integer
---@return integer
local function gutter_width(winid)
  return vim.fn.getwininfo(winid)[1].textoff or 0
end

--- Open or update an overlay window covering the pinned columns.
---
--- The overlay shows the same buffer, so csvview's alignment padding, which lives
--- in buffer extmarks, renders exactly as it does in the main window. It is placed
--- after the main window's gutter and draws no gutter of its own, so its whole
--- width is text and the columns line up.
---@param wins table<integer,integer> winid -> overlay winid
---@param winid integer csvview attached window
---@param view CsvView.View
---@param role "columns"|"corner"
---@param win_opts vim.api.keyset.win_config
---@return integer overlay_winid
local function open_overlay(wins, winid, view, role, win_opts)
  win_opts.win = winid
  win_opts.relative = "win"
  win_opts.col = gutter_width(winid)
  win_opts.focusable = false
  win_opts.style = "minimal"

  local overlay_winid = wins[winid]
  if not overlay_winid or not vim.api.nvim_win_is_valid(overlay_winid) then
    win_opts.noautocmd = true
    overlay_winid = vim.api.nvim_open_win(view.bufnr, false, win_opts)
    wins[winid] = overlay_winid
  else
    vim.api.nvim_win_set_config(overlay_winid, win_opts)
    if vim.api.nvim_win_get_buf(overlay_winid) ~= view.bufnr then
      vim.api.nvim_win_set_buf(overlay_winid, view.bufnr)
    end
  end

  -- Mark as sticky columns window ("columns" or "corner")
  vim.w[overlay_winid].csvview_sticky_columns_win = role

  -- No gutter of its own: the main window already draws one to the left of it.
  local opts = { win = overlay_winid, scope = "local" } ---@type vim.api.keyset.option
  vim.api.nvim_set_option_value("statuscolumn", "", opts)
  vim.api.nvim_set_option_value("signcolumn", "no", opts)
  vim.api.nvim_set_option_value("foldcolumn", "0", opts)
  -- use Normal instead of NormalFloat
  vim.api.nvim_set_option_value("winhighlight", "NormalFloat:Normal", opts)

  -- Same conceal and wrap setup as the csvview window, so `display_mode = "border"`
  -- renders the delimiter here the same way.
  view:setup_window(overlay_winid)

  return overlay_winid
end

--- Scroll an overlay to the given line, with the pinned columns in view.
---@param overlay_winid integer
---@param lnum integer
local function scroll_overlay_to(overlay_winid, lnum)
  vim.api.nvim_win_call(overlay_winid, function()
    local current = vim.fn.winsaveview()
    if current.topline ~= lnum or current.leftcol ~= 0 then
      vim.fn.winrestview({ topline = lnum, lnum = lnum, leftcol = 0 })
    end
  end)
end

--- Display the pinned columns.
---@param winid integer
---@param view CsvView.View
---@param width integer
local function show_sticky_columns(winid, view, width)
  local overlay = open_overlay(M._sticky_columns_wins, winid, view, "columns", {
    width = width,
    height = vim.api.nvim_win_get_height(winid),
    row = 0,
    -- Below the sticky header, which covers the same top row.
    zindex = 45,
  })

  scroll_overlay_to(overlay, vim.api.nvim_win_call(winid, vim.fn.winsaveview).topline)
end

--- Display the pinned columns of the header line, on top of the sticky header.
---
--- The sticky header scrolls horizontally with the window, so without this the
--- header cells of the pinned columns would slide away while their data cells
--- stay put.
---@param winid integer
---@param view CsvView.View
---@param width integer
local function show_corner(winid, view, width)
  local overlay = open_overlay(M._corner_wins, winid, view, "corner", {
    width = width,
    height = 1,
    row = 0,
    -- Above the sticky header.
    zindex = 55,
  })

  scroll_overlay_to(overlay, view.header_lnum)
end

--- Width of the pinned region, or nil if this window has nothing to pin.
---@param winid integer
---@param view CsvView.View
---@return integer?
local function pinned_width(winid, view)
  local opts = view.opts.view.sticky_columns
  if not opts.enabled or opts.count < 1 then
    return nil
  end

  -- Metrics not computed yet, or the buffer has fewer columns than requested.
  local width = view:pinned_width(opts.count)
  if not width or width <= 0 then
    return nil
  end

  -- Never cover the whole text area.
  return math.min(width, vim.api.nvim_win_get_width(winid) - gutter_width(winid) - 1)
end

--- Whether the overlay should currently be drawn.
---
--- Only when something is actually scrolled out of view: at `leftcol == 0` the real
--- columns are already in place. The cursor cannot be caught behind the overlay,
--- since 'sidescrolloff' keeps it to the right of the pinned region.
---@param winid integer
---@return boolean
local function should_show(winid)
  return vim.api.nvim_win_call(winid, vim.fn.winsaveview).leftcol > 0
end

--- Keep the cursor clear of the pinned region.
---
--- The overlay is not focusable, so a cursor underneath it would be invisible.
--- 'sidescrolloff' is the native mechanism for this: it keeps the cursor that many
--- columns away from the window edge, so horizontal scrolling still works normally
--- and the cursor simply never ends up behind the overlay.
---@param winid integer
---@param width integer
local function set_sidescrolloff(winid, width)
  local opts = { win = winid, scope = "local" } ---@type vim.api.keyset.option
  if M._saved_sidescrolloff[winid] == nil then
    M._saved_sidescrolloff[winid] = vim.api.nvim_get_option_value("sidescrolloff", opts)
  end

  local wanted = width + 1
  if vim.api.nvim_get_option_value("sidescrolloff", opts) ~= wanted then
    vim.api.nvim_set_option_value("sidescrolloff", wanted, opts)
  end
end

--- Restore the 'sidescrolloff' the window had before the overlay was shown.
---@param winid integer
local function restore_sidescrolloff(winid)
  local saved = M._saved_sidescrolloff[winid]
  if saved == nil then
    return
  end

  M._saved_sidescrolloff[winid] = nil
  if vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_set_option_value("sidescrolloff", saved, { win = winid, scope = "local" })
  end
end

--- Close one overlay window
---@param wins table<integer,integer> winid -> overlay winid
---@param winid integer
local function close_overlay(wins, winid)
  local overlay = wins[winid]
  if not overlay then
    return
  end

  wins[winid] = nil
  if not vim.api.nvim_win_is_valid(overlay) then
    return
  end

  -- Close (use vim.schedule to avoid issues when called during BufUnload)
  vim.schedule(function()
    if vim.api.nvim_win_is_valid(overlay) then
      pcall(vim.api.nvim_win_close, overlay, true)
    end
  end)
end

--- Close the sticky columns windows of a csvview window
---@param winid integer
function M.close_columns_win_for(winid)
  restore_sidescrolloff(winid)
  close_overlay(M._sticky_columns_wins, winid)
  close_overlay(M._corner_wins, winid)
end

--- Redraw all sticky columns
function M.redraw()
  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local view = win_overlay.get_opened_csvview(winid)
    local width = view and pinned_width(winid, view)
    if not width then
      M.close_columns_win_for(winid)
    elseif not should_show(winid) then
      -- Keep the reservation, drop the overlays.
      set_sidescrolloff(winid, width)
      close_overlay(M._sticky_columns_wins, winid)
      close_overlay(M._corner_wins, winid)
    else
      -- Reserve the room before the overlay is needed, so the cursor is never
      -- caught behind it on the redraw that first scrolls the window.
      set_sidescrolloff(winid, width)
      show_sticky_columns(winid, view, width)

      -- The corner is only needed where a sticky header is actually drawn.
      if view.header_lnum and require("csvview.sticky_header")._sticky_header_wins[winid] then
        show_corner(winid, view, width)
      else
        close_overlay(M._corner_wins, winid)
      end
    end
  end
end

return M
