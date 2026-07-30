local win_overlay = require("csvview.win_overlay")

local M = {}

M._sticky_columns_wins = {} --- @type table<integer,integer> winid -> sticky-columns winid
M._saved_sidescrolloff = {} --- @type table<integer,integer> winid -> 'sidescrolloff' before pinning

--- Sync the vertical scroll of the sticky columns window with the main window.
---
--- The overlay shows the same buffer with `leftcol` held at 0, so the pinned columns
--- stay in place while the main window scrolls horizontally.
---@param winid integer csvview attached window
---@param columns_winid integer sticky-columns window
local function sync_vertical_scroll(winid, columns_winid)
  local win_view = vim.api.nvim_win_call(winid, vim.fn.winsaveview) ---@type vim.fn.winsaveview.ret
  vim.api.nvim_win_call(columns_winid, function()
    local current = vim.fn.winsaveview()
    if current.topline ~= win_view.topline or current.leftcol ~= 0 then
      vim.fn.winrestview({ topline = win_view.topline, lnum = win_view.topline, leftcol = 0 })
    end
  end)
end

--- Display sticky columns.
---@param winid integer
---@param view CsvView.View
---@param width integer
local function show_sticky_columns(winid, view, width)
  -- Same approach as the sticky header, rotated 90 degrees: a floating window showing
  -- the same buffer. Since csvview's alignment padding lives in buffer extmarks, the
  -- overlay renders the columns exactly as the main window does.
  local win_opts = { ---@type vim.api.keyset.win_config
    win = winid,
    relative = "win",
    width = width,
    height = vim.api.nvim_win_get_height(winid),
    row = 0,
    col = 0,
    focusable = false,
    style = "minimal",
    -- Keep the sticky header, which is created at the same position, on top.
    zindex = 45,
  }

  local columns_winid = M._sticky_columns_wins[winid]
  if not columns_winid or not vim.api.nvim_win_is_valid(columns_winid) then
    win_opts.noautocmd = true
    columns_winid = vim.api.nvim_open_win(view.bufnr, false, win_opts)
    M._sticky_columns_wins[winid] = columns_winid
  else
    vim.api.nvim_win_set_config(columns_winid, win_opts)
    if vim.api.nvim_win_get_buf(columns_winid) ~= view.bufnr then
      vim.api.nvim_win_set_buf(columns_winid, view.bufnr)
    end
  end

  -- Mark as sticky columns window
  vim.w[columns_winid].csvview_sticky_columns_win = true

  win_overlay.setup_overlay_win_options(columns_winid, winid)
  vim.api.nvim_set_option_value("wrap", false, { win = columns_winid, scope = "local" })
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

  -- Never cover the whole window.
  local gutter = vim.fn.getwininfo(winid)[1].textoff or 0
  return math.min(width, vim.api.nvim_win_get_width(winid) - gutter - 1)
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

--- Close the sticky columns window of a csvview window
---@param winid integer
function M.close_columns_win_for(winid)
  restore_sidescrolloff(winid)

  local columns_win = M._sticky_columns_wins[winid]
  if not columns_win then
    return
  end

  M._sticky_columns_wins[winid] = nil
  if not vim.api.nvim_win_is_valid(columns_win) then
    return
  end

  -- Close (use vim.schedule to avoid issues when called during BufUnload)
  vim.schedule(function()
    if vim.api.nvim_win_is_valid(columns_win) then
      pcall(vim.api.nvim_win_close, columns_win, true)
    end
  end)
end

--- Redraw all sticky columns
function M.redraw()
  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local view = win_overlay.get_opened_csvview(winid)
    local width = view and pinned_width(winid, view)
    if not width then
      M.close_columns_win_for(winid)
    else
      -- Reserve the room before the overlay is needed, so the cursor is never
      -- caught behind it on the redraw that first scrolls the window.
      set_sidescrolloff(winid, width)
      if should_show(winid) then
        show_sticky_columns(winid, view, width)
        sync_vertical_scroll(winid, M._sticky_columns_wins[winid])
      elseif M._sticky_columns_wins[winid] then
        local columns_win = M._sticky_columns_wins[winid]
        M._sticky_columns_wins[winid] = nil
        vim.schedule(function()
          if vim.api.nvim_win_is_valid(columns_win) then
            pcall(vim.api.nvim_win_close, columns_win, true)
          end
        end)
      end
    end
  end
end

return M
