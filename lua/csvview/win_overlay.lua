--- Helpers shared by the floating windows that overlay a csvview window
--- (`sticky_header`, `sticky_columns`).
local M = {}

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

  local num = vim.api.nvim_get_option_value("number", { win = winid, scope = "local" }) ---@type boolean
  local trailing_space = num and " " or ""
  return "%C%=%s%=%l" .. trailing_space
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
function M.copy_win_options(names, source, target)
  for _, name in ipairs(names) do
    local value = vim.api.nvim_get_option_value(name, { win = source, scope = "local" })
    vim.api.nvim_set_option_value(name, value, { win = target, scope = "local" })
  end
end

--- statuscolumn function for an overlay window.
---@param winid integer csvview attached window
---@return string statuscolumn
function M.statuscolumn(winid)
  if not vim.api.nvim_win_is_valid(winid) then
    return ""
  end

  -- Evaluate the status column in the original window and reflect the result in the overlay window.
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

--- Mirror the gutter and number-related options of the csvview window onto an overlay window.
---@param overlay_winid integer
---@param winid integer csvview attached window
function M.setup_overlay_win_options(overlay_winid, winid)
  local opts = { ---@type vim.api.keyset.option
    win = overlay_winid,
    scope = "local",
  }

  -- Set special statuscolumn for the overlay window
  local statuscolumn = string.format("%%{%%v:lua.require('csvview.win_overlay').statuscolumn(%d)%%}", winid)
  vim.api.nvim_set_option_value("statuscolumn", statuscolumn, opts)

  -- use Normal instead of NormalFloat
  vim.api.nvim_set_option_value("winhighlight", "NormalFloat:Normal", opts)

  -- Copy window options from the main window to the overlay window
  M.copy_win_options({
    "relativenumber",
    "signcolumn",
    "foldcolumn",
    "numberwidth",
  }, winid, overlay_winid)
end

--- Get the CsvView.View displayed in the window, if any.
---
--- Returns nil for windows that are themselves csvview overlays.
---@param winid integer window ID
---@return CsvView.View? view
function M.get_opened_csvview(winid)
  if not vim.api.nvim_win_is_valid(winid) then
    return
  end

  -- overlay window
  if vim.w[winid].csvview_sticky_header_win or vim.w[winid].csvview_sticky_columns_win then
    return
  end

  local bufnr = vim.api.nvim_win_get_buf(winid)
  return require("csvview.view").get(bufnr)
end

return M
