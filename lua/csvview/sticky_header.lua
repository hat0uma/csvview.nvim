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

--- Get the 'statuscolumn' option of the window, or the default value if it is empty.
---@param winid integer window ID
---@return string
local function get_statuscolumn_or_default(winid)
  local statuscolumn = vim.api.nvim_get_option_value("statuscolumn", { win = winid, scope = "local" }) ---@type string
  if statuscolumn ~= "" then
    return statuscolumn
  end

  -- default
  if vim.fn.has("nvim-0.11") ~= 1 then
    -- below neovim 0.11
    -- https://github.com/neovim/neovim/pull/29357
    local relnum = vim.api.nvim_get_option_value("relativenumber", { win = winid, scope = "local" }) ---@type boolean
    return relnum and "%C%=%s%=%r " or "%C%=%s%=%l "
  end

  return "%C%=%s%=%l "
end

--- Convert the dictionary returned by nvim_eval_statusline() into a
--- 'statuscolumn'-compatible string that reproduces the highlights.
--- @param eval_result { str: string, width: number, highlights: {start: number, group:string, groups: string[] }[] } A dictionary from nvim_eval_statusline()
--- @return string converted A string in 'statuscolumn' format.
local function format_to_stc_string(eval_result)
  local text = eval_result.str or ""
  local highlights = eval_result.highlights
  if not highlights or #highlights == 0 then
    return text
  end

  local pieces = {}
  for i, hl in ipairs(highlights) do
    local start_index = hl.start
    local end_index = (i < #highlights) and highlights[i + 1].start or #text
    -- Extract the string corresponding to the current segment
    local segment = string.sub(text, start_index + 1, end_index)

    -- Use the last highlight group
    local groups = hl.groups or { hl.group } -- fallback to hl.group for compatibility
    local group_name = #groups > 0 and groups[#groups] or "Normal"

    -- %#…# to start highlight, %* to end highlight
    table.insert(pieces, "%#" .. group_name .. "#" .. segment .. "%*")
  end

  return table.concat(pieces)
end

--- Copy window options from one window to another
--- @param names string[]: List of option names to copy
--- @param source integer: Source window ID
--- @param target integer: Target window ID
local function copy_win_options(names, source, target)
  for _, name in ipairs(names) do
    local value = vim.api.nvim_get_option_value(name, { win = source, scope = "local" })
    vim.api.nvim_set_option_value(name, value, { win = target, scope = "local" })
  end
end

--- Set window options for the sticky header window
---@param sticky_header_winid integer
---@param winid integer
local function set_sticky_header_win_options(sticky_header_winid, winid)
  local opts = { ---@type vim.api.keyset.option
    win = sticky_header_winid,
    scope = "local",
  }

  -- Set special statuscolumn for sticky header window
  local statuscolumn = string.format("%%{%%v:lua.require('csvview.sticky_header').statuscolumn(%d)%%}", winid)
  vim.api.nvim_set_option_value("statuscolumn", statuscolumn, opts)

  -- use Normal instead of NormalFloat
  vim.api.nvim_set_option_value("winhighlight", "NormalFloat:Normal", opts)

  -- Copy window options from the main window to the sticky header window
  copy_win_options({
    "relativenumber",
    "signcolumn",
    "foldcolumn",
    "numberwidth",
  }, winid, sticky_header_winid)
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
  set_sticky_header_win_options(sticky_header_winid, winid)
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
  local header_lnum = view.opts.view.header_lnum
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

--- Get the CsvView.View that is displayed in the window.
---@param winid integer window ID
---@return CsvView.View? view
local function get_opened_csvview(winid)
  if not vim.api.nvim_win_is_valid(winid) then
    return
  end

  -- sticky header window
  if vim.w[winid].csvview_sticky_header_win then
    return
  end

  local bufnr = vim.api.nvim_win_get_buf(winid)
  local view = require("csvview.view").get(bufnr)
  return view
end

--- Close header window
---@param winid integer
function M.close_if_opened(winid)
  local header_win = M._sticky_header_wins[winid]
  if not header_win then
    return
  end

  -- Close
  if vim.api.nvim_win_is_valid(header_win) then
    vim.api.nvim_win_close(header_win, true)
  end
  M._sticky_header_wins[winid] = nil
end

--- statuscolumn function for sticky header window.
---@param winid integer csvview attached window
---@return string statuscolumn
function M.statuscolumn(winid)
  -- Evaluate the status column in the original window and reflect the result in the sticky header window.
  -- This allows correct display of things like relativenumber.
  local statuscolumn = get_statuscolumn_or_default(winid)
  local data = vim.api.nvim_eval_statusline(statuscolumn, {
    use_statuscol_lnum = vim.v.lnum,
    winid = winid,
    highlights = true,
    fillchar = " ",
  })

  ---@diagnostic disable-next-line: param-type-mismatch
  return format_to_stc_string(data)
end

--- Redraw all sticky headers
function M.redraw()
  local wins = vim.api.nvim_tabpage_list_wins(0)
  for _, winid in ipairs(wins) do
    local view = get_opened_csvview(winid)
    if view and should_show_sticky_header(winid, view) then
      show_sticky_header(winid, view)
      sync_horizontal_scroll(winid, M._sticky_header_wins[winid], view.opts.view.header_lnum)
    else
      M.close_if_opened(winid)
    end
  end
end

return M
