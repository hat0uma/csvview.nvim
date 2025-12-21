local M = {}
local util = require("csvview.util")
local views = require("csvview.view")

local EXTMARK_NS = vim.api.nvim_create_namespace("csvview_info")

--- Highlight groups for info display
local HL_GROUPS = {
  TITLE = "CsvViewInfoTitle",
  SECTION = "CsvViewInfoSection",
  KEY = "CsvViewInfoKey",
  VALUE = "CsvViewInfoValue",
  VALUE_HIGHLIGHT = "CsvViewInfoValueHighlight",
  BAR = "CsvViewInfoBar",
  TABLE_HEADER = "CsvViewInfoTableHeader",
  TABLE_BORDER = "CsvViewInfoTableBorder",
  ICON_POSITIVE = "CsvViewInfoIconPositive",
  ICON_NEGATIVE = "CsvViewInfoIconNegative",
  ICON_NEUTRAL = "CsvViewInfoIconNeutral",
  LEGEND = "CsvViewInfoLegend",
}

local function format_delimiter(delimiter)
  local map = { ["\t"] = "(tab)", [" "] = "(space)" }
  return map[delimiter] or delimiter
end

local function format_line(line)
  return line and string.format("Line:%d", line) or "N/A"
end

local function format_detection_status(is_auto)
  return is_auto and "(Auto)" or "(Manual)"
end

--- Format score icon
---@param score number?
---@return CsvViewInfo.Chunk
local function format_score_icon(score)
  if not score or score == 0 then
    return { ".", HL_GROUPS.ICON_NEUTRAL }
  elseif score > 0 then
    return { "+", HL_GROUPS.ICON_POSITIVE }
  else
    return { "-", HL_GROUPS.ICON_NEGATIVE }
  end
end

---@class CsvViewInfo.Chunk
---@field [1] string text
---@field [2] string? highlight group

---@class CsvViewInfo.Line
---@field chunks CsvViewInfo.Chunk[]

---@class CsvViewInfo.ContentBuilder
---@field content CsvViewInfo.Line[]
local ContentBuilder = {}
ContentBuilder.__index = ContentBuilder

function ContentBuilder.new()
  return setmetatable({ content = {} }, ContentBuilder)
end

--- Add a line composed of chunks
--- Each chunk is {text, hl_group} where hl_group is optional
---@param chunks CsvViewInfo.Chunk[]
function ContentBuilder:line(chunks)
  table.insert(self.content, { chunks = chunks })
end

--- Add empty line
function ContentBuilder:blank()
  self:line({ { "" } })
end

--- Add empty line if last line is not empty
function ContentBuilder:ensure_blank()
  if #self.content > 0 then
    local last = self.content[#self.content]
    local last_text = ""
    for _, chunk in ipairs(last.chunks) do
      last_text = last_text .. chunk[1]
    end
    if last_text ~= "" then
      self:blank()
    end
  end
end

--- Add title line
---@param title string
function ContentBuilder:title(title)
  self:line({ { title, HL_GROUPS.TITLE } })
end

--- Add section header
---@param title string
function ContentBuilder:section(title)
  self:ensure_blank()
  self:line({ { title, HL_GROUPS.SECTION } })
end

--- Add key-value pair
---@param key string
---@param value_chunks CsvViewInfo.Chunk[]
function ContentBuilder:kv(key, value_chunks)
  local chunks = {
    { "  " },
    { string.format("%-13s", key), HL_GROUPS.KEY },
    { " : " },
  }
  for _, vc in ipairs(value_chunks) do
    table.insert(chunks, vc)
  end
  self:line(chunks)
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
    self:kv(display_key, {
      { string.format("%5.3f", score), HL_GROUPS.VALUE_HIGHLIGHT },
      { " " },
      { bar, HL_GROUPS.BAR },
    })
  end
  self:blank()
end

---Add header detection details
---@param reason string | CsvView.Sniffer.HeaderDetectionReason
function ContentBuilder:add_header_detection_details(reason)
  if type(reason) == "string" then
    self:line({ { "  " }, { reason, HL_GROUPS.LEGEND } })
    return
  end

  -- Add Total Score
  if reason.total_score then
    local lnum = format_line(reason.candidate_lnum)
    self:line({
      { "  " },
      { lnum, HL_GROUPS.VALUE_HIGHLIGHT },
      { " is header candidate (Total Score: " },
      { string.format("%+.1f", reason.total_score), HL_GROUPS.VALUE_HIGHLIGHT },
      { ")" },
    })
  end

  -- Column Analysis
  if #reason.columns == 0 then
    return
  end

  -- Table header
  self:blank()
  self:line({ { "  Col   Score    Type           Length(Data/Head)", HL_GROUPS.TABLE_HEADER } })
  self:line({ { "  " .. string.rep("─", 45), HL_GROUPS.TABLE_BORDER } })

  -- Generate rows
  for _, col in ipairs(reason.columns) do
    local s = col.length_stats
    self:line({
      { string.format("  %3d   %+5.1f   ", col.col_idx, col.score) },
      format_score_icon(col.type_score),
      { string.format(" %-10.10s  ", col.detected_type or "text/mixed") },
      format_score_icon(col.length_score),
      { string.format(" %4.1f-%-4.1f / %2d", math.max(0, s.min), s.max, s.val) },
    })
  end

  -- Legend
  self:blank()
  local legend_lines = {
    "  Type (±1.0)",
    "    + Type differs from data (Header-like)",
    "    - Type matches data (Data-like)",
    "    . Ambiguous (No score)",
    "",
    "  Length (±0.5)",
    "    + Header length is outlier (Header-like)",
    "    - Header length is normal (Data-like)",
    "",
  }
  for _, legend in ipairs(legend_lines) do
    self:line({ { legend, HL_GROUPS.LEGEND } })
  end
end

--- Build lines and extmarks from content
---@return string[] lines
---@return CsvViewInfo.Extmark[] extmarks
function ContentBuilder:build()
  local lines = {}
  local extmarks = {}

  for row_idx, line_data in ipairs(self.content) do
    local line_text = ""
    for _, chunk in ipairs(line_data.chunks) do
      local text = chunk[1]
      local hl = chunk[2]
      local col_start = #line_text
      line_text = line_text .. text
      if hl then
        table.insert(extmarks, {
          row = row_idx - 1, -- 0-indexed
          col = col_start,
          opts = { end_col = #line_text, hl_group = hl },
        })
      end
    end
    table.insert(lines, line_text)
  end

  return lines, extmarks
end

---@class CsvViewInfo.Extmark
---@field row integer 0-indexed row
---@field col integer 0-indexed column
---@field opts vim.api.keyset.set_extmark

--- Generate the content for the buffer
---@param bufnr integer
---@param metrics CsvView.Metrics
---@param info CsvView.Info
---@return string[] lines
---@return CsvViewInfo.Extmark[] extmarks
local function generate_info_content(bufnr, metrics, info)
  local builder = ContentBuilder.new()
  builder:section("Overview")

  -- File
  local filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t")
  if filename and filename ~= "" then
    builder:kv("File", { { filename, HL_GROUPS.VALUE } })
  end

  -- Size
  local rows = metrics:row_count_logical()
  local cols = metrics:column_count()
  builder:kv("Size", {
    { tostring(rows), HL_GROUPS.VALUE_HIGHLIGHT },
    { " rows × " },
    { tostring(cols), HL_GROUPS.VALUE_HIGHLIGHT },
    { " cols" },
  })

  -- Delimiter
  local delimiter = format_delimiter(info.delimiter.text)
  local delimiter_status = format_detection_status(info.delimiter.auto_detected)
  builder:kv("Delimiter", {
    { delimiter, HL_GROUPS.VALUE_HIGHLIGHT },
    { " " .. delimiter_status, HL_GROUPS.VALUE },
  })

  -- Quote
  local quote_char = format_delimiter(info.quote_char.text)
  local quote_char_status = format_detection_status(info.quote_char.auto_detected)
  builder:kv("Quote", {
    { quote_char, HL_GROUPS.VALUE_HIGHLIGHT },
    { " " .. quote_char_status, HL_GROUPS.VALUE },
  })

  -- Header Info
  local header_status = format_detection_status(info.header.auto_detected)
  local header_val = format_line(info.header.lnum)
  builder:kv("Header", {
    { header_val, HL_GROUPS.VALUE_HIGHLIGHT },
    { " " .. header_status, HL_GROUPS.VALUE },
  })

  -- Evidences
  if info.delimiter.auto_detected then
    builder:section("Delimiter Confidence")
    builder:add_detection_scores(info.delimiter.scores)
  end
  if info.quote_char.auto_detected then
    builder:section("Quote Confidence")
    builder:add_detection_scores(info.quote_char.scores)
  end
  if info.header.reason then
    builder:section("Header Analysis")
    builder:add_header_detection_details(info.header.reason)
  end

  return builder:build()
end

--- Apply extmarks to buffer
---@param bufnr integer
---@param extmarks CsvViewInfo.Extmark[]
local function apply_extmarks(bufnr, extmarks)
  for _, extmark in ipairs(extmarks) do
    vim.api.nvim_buf_set_extmark(bufnr, EXTMARK_NS, extmark.row, extmark.col, extmark.opts)
  end
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
  local lines, extmarks = generate_info_content(bufnr, view.metrics, info)

  -- Create Buffer
  local infobuf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(infobuf, 0, -1, false, lines)
  apply_extmarks(infobuf, extmarks)
  vim.bo[infobuf].modifiable = false
  vim.bo[infobuf].bufhidden = "wipe"

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

  local winopts = {
    winhl = "Normal:NormalFloat,FloatBorder:FloatBorder,FloatTitle:CsvViewInfoTitle",
    winfixbuf = true,
  }
  for name, value in pairs(winopts) do
    vim.api.nvim_set_option_value(name, value, { win = win })
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
