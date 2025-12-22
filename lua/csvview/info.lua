local M = {}
local util = require("csvview.util")
local views = require("csvview.view")
local HL = require("csvview.config").highlights

local EXTMARK_NS = vim.api.nvim_create_namespace("csvview_info")

local function format_delimiter(delimiter)
  local map = { ["\t"] = "(tab)", [" "] = "(space)" }
  return map[delimiter] or delimiter
end

local function format_line(line)
  return line and string.format("Line %d", line) or "N/A"
end

local function format_detection_status(is_auto)
  return is_auto and "(Auto)" or "(Manual)"
end

--- Format type check result for table
---@param col CsvView.Sniffer.ColumnEvidence
---@return CsvViewInfo.Chunk[]
local function format_type_check(col)
  if col.type_score == 0 or not col.detected_type then
    return { { "-", HL.InfoNeutral } }
  end

  if col.type_score > 0 then
    local detected_type = string.format(" (Data: %s)", col.detected_type)
    return { { "Yes", HL.InfoPositive }, { detected_type } }
  else
    local detected_type = string.format(" (Both: %s)", col.detected_type)
    return { { " No", HL.InfoNegative }, { detected_type } }
  end
end

--- Format length check result for table
---@param col CsvView.Sniffer.ColumnEvidence
---@return CsvViewInfo.Chunk[]
local function format_length_check(col)
  local s = col.length_stats
  if col.length_score > 0 then
    return { { "Yes ", HL.InfoPositive }, { s.val < s.min and "(Short)" or "(Long) " } }
  else
    return { { "No         ", HL.InfoNegative } }
  end
end

--- Calculate total display width of chunks
---@param chunks CsvViewInfo.Chunk[]
---@return integer
local function chunks_width(chunks)
  local width = 0
  for _, c in ipairs(chunks) do
    width = width + vim.api.nvim_strwidth(c[1])
  end
  return width
end

--- Append chunks to target with optional fixed width padding
---@param target CsvViewInfo.Chunk[]
---@param chunks CsvViewInfo.Chunk[]
---@param width integer? Fixed width to pad to
local function append_chunks(target, chunks, width)
  for _, c in ipairs(chunks) do
    table.insert(target, c)
  end
  if width then
    local padding = width - chunks_width(chunks)
    if padding > 0 then
      table.insert(target, { string.rep(" ", padding) })
    end
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

--- Add section header
---@param title string
function ContentBuilder:section(title)
  self:ensure_blank()
  self:line({ { title, HL.InfoSection } })
end

--- Add key-value pair
---@param key string
---@param value_chunks CsvViewInfo.Chunk[]
function ContentBuilder:kv(key, value_chunks)
  local chunks = {
    { "  " },
    { string.format("%-13s", key), HL.InfoLabel },
    { " : " },
  }
  for _, vc in ipairs(value_chunks) do
    table.insert(chunks, vc)
  end
  self:line(chunks)
end

--- Add a table with auto-calculated column widths
---@param header CsvViewInfo.Chunk[][] Header row (array of column chunks)
---@param rows CsvViewInfo.Chunk[][][] Data rows (array of rows, each row is array of column chunks)
---@param opts? { indent?: integer,gap?:integer, border_char?: string, border_hl?: string }
function ContentBuilder:add_table(header, rows, opts)
  opts = opts or {}
  local indent = string.rep(" ", opts.indent or 2)
  local col_count = #header
  local gap = opts.gap or 2

  -- Calculate max width for each column
  local col_widths = {} ---@type integer[]
  for col_idx = 1, col_count do
    col_widths[col_idx] = chunks_width(header[col_idx]) + gap
  end
  for _, row in ipairs(rows) do
    for col_idx = 1, col_count do
      if row[col_idx] then
        col_widths[col_idx] = math.max(col_widths[col_idx], chunks_width(row[col_idx]) + gap)
      end
    end
  end

  -- Render header
  local header_chunks = { { indent } }
  for col_idx, col in ipairs(header) do
    local width = col_idx < col_count and col_widths[col_idx] or nil
    append_chunks(header_chunks, col, width)
  end
  self:line(header_chunks)

  -- Render border
  local total_width = 0
  for _, w in ipairs(col_widths) do
    total_width = total_width + w
  end
  local border_char = opts.border_char or "─"
  local border = { { indent .. string.rep(border_char, total_width), opts.border_hl } }
  self:line(border)

  -- Render rows
  for _, row in ipairs(rows) do
    local row_chunks = { { indent } }
    for col_idx = 1, col_count do
      local col = row[col_idx] or { { "" } }
      local width = col_idx < col_count and col_widths[col_idx] or nil
      append_chunks(row_chunks, col, width)
    end
    self:line(row_chunks)
  end

  -- Render border
  self:line(border)
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

  -- Score bar and values
  for _, k in ipairs(sorted_keys) do
    local display_key = format_delimiter(k)
    local score = scores[k]
    local bar = string.rep("█", math.floor(score * 10))
    self:kv(display_key, {
      { string.format("%5.3f", score), HL.InfoNumber },
      { " " },
      { bar, HL.InfoScoreBar },
    })
  end
  self:blank()
end

---Add header detection details
---@param reason string | CsvView.Sniffer.HeaderDetectionReason
function ContentBuilder:add_header_detection_details(reason)
  if type(reason) == "string" then
    self:line({ { "  " }, { reason, HL.InfoHint } })
    return
  end

  -- Score summary with judgment
  if reason.total_score then
    local judgment = reason.total_score > 0 and "Likely Header" or "Likely Data"
    local judgment_hl = reason.total_score > 0 and HL.InfoPositive or HL.InfoNegative
    local score = string.format("%+.1f", reason.total_score)
    self:line({ { "  Score: " }, { score, HL.InfoNumber }, { " (" }, { judgment, judgment_hl }, { ")" } })
  end

  -- Column Analysis
  if #reason.columns == 0 then
    return
  end

  -- Details table
  self:blank()
  self:line({ { "  Details:", HL.InfoLabel } })

  local header = {
    { { "Col" } },
    { { "Type Mismatch?" }, { "[±1.0]", HL.InfoHint } },
    { { "Length Outlier?" }, { "[±0.5]", HL.InfoHint } },
    { { "Score" } },
  }
  local rows = {}
  for _, col in ipairs(reason.columns) do
    table.insert(rows, {
      { { string.format("%3d", col.col_idx) } },
      format_type_check(col),
      format_length_check(col),
      { { string.format("%+5.1f", col.score) } },
    })
  end
  self:add_table(header, rows, {
    border_hl = HL.InfoTableBorder,
    header_line_hl = HL.InfoTableHeader,
    gap = 2,
  })
  self:blank()

  -- Debug Information
  self:line({ { "  Debug:", HL.InfoLabel } })
  local d = vim.split(vim.inspect(reason), "\n")
  for _, l in ipairs(d) do
    self:line({ { "  " .. l, HL.InfoHint } })
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
local function generate_report(bufnr, metrics, info)
  local builder = ContentBuilder.new()
  builder:section("Overview")

  -- File
  local filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t")
  if filename and filename ~= "" then
    builder:kv("File", { { filename, HL.InfoText } })
  end

  -- Dimensions
  local rows = metrics:row_count_logical()
  local cols = metrics:column_count()
  builder:kv("Dimensions", {
    { tostring(rows), HL.InfoNumber },
    { " rows × " },
    { tostring(cols), HL.InfoNumber },
    { " cols" },
  })

  -- Delimiter
  local delimiter = format_delimiter(info.delimiter.text)
  local delimiter_status = format_detection_status(info.delimiter.auto_detected)
  builder:kv("Delimiter", {
    { delimiter, HL.InfoNumber },
    { " " .. delimiter_status, HL.InfoText },
  })

  -- Quote
  local quote_char = format_delimiter(info.quote_char.text)
  local quote_char_status = format_detection_status(info.quote_char.auto_detected)
  builder:kv("Quote", {
    { quote_char, HL.InfoNumber },
    { " " .. quote_char_status, HL.InfoText },
  })

  -- Header Info
  local header_status = format_detection_status(info.header.auto_detected)
  local header_val = format_line(info.header.lnum)
  builder:kv("Header", {
    { header_val, HL.InfoNumber },
    { " " .. header_status, HL.InfoText },
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
    local header_section_title = "Header Analysis"
    if type(info.header.reason) == "table" and info.header.reason.candidate_lnum then
      header_section_title = string.format("Header Analysis (Line %d)", info.header.reason.candidate_lnum)
    end
    builder:section(header_section_title)
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
  local lines, extmarks = generate_report(bufnr, view.metrics, info)

  -- Create Buffer
  local infobuf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(infobuf, 0, -1, false, lines)
  apply_extmarks(infobuf, extmarks)
  vim.bo[infobuf].modifiable = false
  vim.bo[infobuf].bufhidden = "wipe"
  vim.bo[infobuf].filetype = "csvview-info"

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
