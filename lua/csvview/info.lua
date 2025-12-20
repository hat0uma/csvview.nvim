local M = {}
local util = require("csvview.util")
local views = require("csvview.view")

local ICONS = {
  OK = "**+**",
  NG = "-",
  OTHER = ".",
}

local function format_delimiter(delimiter)
  local map = { ["\t"] = "(tab)", [" "] = "(space)" }
  return map[delimiter] or delimiter
end

local function format_line(line)
  return line and string.format("Line:`%d`", line) or "`N/A`"
end

local function format_detection_status(is_auto)
  return is_auto and "(Auto)" or "(Manual)"
end

---@class ContentBuilder
---@field lines string[]
local ContentBuilder = {}
ContentBuilder.__index = ContentBuilder

function ContentBuilder.new()
  return setmetatable({ lines = {} }, ContentBuilder)
end

--- Add line
---@param str string
function ContentBuilder:add(str)
  table.insert(self.lines, str)
end

--- Add line with format
---@param fmt string
---@param ... any
function ContentBuilder:addf(fmt, ...)
  table.insert(self.lines, string.format(fmt, ...))
end

--- Add key value
---@param key string
---@param value string
---@param bquote boolean?
function ContentBuilder:kv(key, value, bquote)
  if bquote then
    table.insert(self.lines, string.format("- `%-13s` : %s", key, value))
  else
    table.insert(self.lines, string.format("- %-13s : %s", key, value))
  end
end

--- Add new section
---@param title string
---@param level integer
function ContentBuilder:section(title, level)
  if #self.lines > 0 and self.lines[#self.lines] ~= "" then
    self:add("")
  end

  local head = string.rep("#", level)
  self:addf("%s %s", head, title)
end

---Add Confidence scores
---@param scores table<string, number>
function ContentBuilder:add_detection_scores(scores)
  if not scores then
    return
  end

  local sorted_keys = vim.tbl_keys(scores) ---@type string[]
  table.sort(sorted_keys, function(a, b)
    return scores[a] > scores[b]
  end)

  for _, k in ipairs(sorted_keys) do
    local display_key = format_delimiter(k)
    local score = scores[k]
    local bar = string.rep("█", math.floor(score * 10))
    self:kv(display_key, string.format("%5.3f %s", score, bar), true)
  end
  self:add("")
end

---Add header detection details
---@param reason string | CsvView.Sniffer.HeaderDetectionReason
function ContentBuilder:add_header_detection_details(reason)
  if type(reason) == "string" then
    self:add(reason)
    return
  end

  -- Add Total Score
  if reason.total_score then
    local lnum = format_line(reason.candidate_lnum)
    self:addf("%s is header candidate (Total Score: `%+.1f`).", lnum, reason.total_score)
  end

  -- Column Analysis
  if #reason.columns == 0 then
    return
  end

  -- Define table header
  local header_fmt = "| %-5s | %-6s | %-12s | %-20s |"
  local row_fmt = "| %5d | %+6.1f | %s %-10.10s | %s D:%4.1f-%4.1f / H:%-2d |"
  self:add("")
  self:addf(header_fmt, "Col", "Score", "Type", "Length (Data/Head)")
  self:addf(
    "|%s|%s|%s|%s|",
    string.rep("-", 5 + 2),
    string.rep("-", 6 + 2),
    string.rep("-", 12 + 2),
    string.rep("-", 20 + 2)
  )
  -- Generate
  for _, col in ipairs(reason.columns) do
    local type_icon = col.type_score > 0 and ICONS.OK or (col.type_score < 0 and ICONS.NG or ICONS.OTHER)
    local len_icon = col.length_score >= 0 and ICONS.OK or ICONS.NG

    local s = col.length_stats
    self:addf(
      row_fmt,
      col.col_idx,
      col.score,
      type_icon,
      col.detected_type or "text/mixed",
      len_icon,
      math.max(0, s.min),
      s.max,
      s.val
    )
  end

  self:add("---")
  self:add("- Type (`±1.0`)")
  self:add("  - `+` Type differs from data (Header-like)")
  self:add("  - `-` Type matches data (Data-like)")
  self:add("  - `.` Ambiguous(No score)")
  self:add("- Length (`±0.5`)")
  self:add("  - `+` Length is outlier (Header-like)")
  self:add("  - `-` Length is normal (Data-like)")
end

--- Generate the lines for the buffer
---@param view CsvView.View
---@param info CsvView.Info
---@return string[]
local function generate_info_lines(view, info)
  local builder = ContentBuilder.new()

  builder:section("CsvView Info", 1)
  builder:section("File Specs", 2)

  -- Size
  local rows = view.metrics:row_count_logical()
  local cols = view.metrics:column_count()
  builder:kv("Size", string.format("`%d` rows × `%d` cols", rows, cols))

  -- Delimiter
  local delimiter = format_delimiter(info.delimiter.text)
  local delimiter_status = format_detection_status(info.delimiter.auto_detected)
  builder:kv("Delimiter", string.format("`%-8s` %s", delimiter, delimiter_status))

  -- Quote
  local quote_char = format_delimiter(info.quote_char.text)
  local quote_char_status = format_detection_status(info.quote_char.auto_detected)
  builder:kv("Quote", string.format("`%-8s` %s", quote_char, quote_char_status))

  -- Header Info
  local header_status = format_detection_status(info.header.auto_detected)
  local header_val = format_line(info.header.lnum)
  builder:kv("Header", string.format("%-10s %s", header_val, header_status))

  -- Evidences
  if info.delimiter.auto_detected then
    builder:section("Delimiter Scores", 2)
    builder:add_detection_scores(info.delimiter.scores)
  end
  if info.quote_char.auto_detected then
    builder:section("Quote Scores", 2)
    builder:add_detection_scores(info.quote_char.scores)
  end
  if info.header.reason then
    builder:section("Header Analysis", 2)
    builder:add_header_detection_details(info.header.reason)
  end

  return builder.lines
end

--- Show csvview info
---@param bufnr integer?
function M.show(bufnr)
  bufnr = util.resolve_bufnr(bufnr)
  local view = views.get(bufnr)
  if not view then
    vim.notify("csvview: not enabled for this buffer.", vim.log.levels.WARN)
    return
  end

  local info = vim.b[bufnr].csvview_info
  if not info then
    vim.notify("csvview: no info available for this buffer.", vim.log.levels.WARN)
    return
  end

  -- Generate Content
  local lines = generate_info_lines(view, info)

  -- Create Buffer
  local infobuf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(infobuf, 0, -1, false, lines)
  vim.bo[infobuf].filetype = "markdown"
  vim.bo[infobuf].modifiable = false

  -- Calculate Dimensions
  local width = math.min(math.floor(vim.o.columns * 0.7), 85)
  local height = math.min(math.floor(vim.o.lines * 0.7), #lines + 4)
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)

  -- Create Window
  local win = vim.api.nvim_open_win(infobuf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = col,
    row = row,
    style = "minimal",
    border = "rounded",
    title = " CsvView Info ",
    title_pos = "center",
  })

  -- Window Options
  local win_opts = {
    winhl = "Normal:NormalFloat,FloatBorder:FloatBorder",
    winfixbuf = true,
    conceallevel = 2,
    concealcursor = "nvic",
  }
  for k, v in pairs(win_opts) do
    vim.api.nvim_set_option_value(k, v, { win = win })
  end

  -- Keymaps
  local close_keys = { "q", "<Esc>" }
  for _, key in ipairs(close_keys) do
    vim.keymap.set("n", key, function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end, { buffer = infobuf, nowait = true })
  end
end

return M
