local EXTMARK_NS = vim.api.nvim_create_namespace("csv_extmark")
local BORDER_CHAR = "│"

local util = require("csvview.util")
local KIND = require("csvview.metrics_store").KIND

--- Set local option for window
---@param winid integer
---@param key string
---@param value any
local function set_local(winid, key, value)
  local opts = { scope = "local", win = winid }
  if vim.api.nvim_get_option_value(key, opts) ~= value then
    vim.api.nvim_set_option_value(key, value, opts)
  end
end

--- @class CsvView.View
--- @field public bufnr integer
--- @field public metrics CsvView.Metrics
--- @field public opts CsvView.InternalOptions
--- @field public header_lnum integer? 1-indexed line number of header
--- @field private _extmarks table<integer,integer[]> 1-based line -> extmark ids
--- @field private _on_dispose function? called when view is disposed
--- @field private _locked boolean
local View = {}

--- Resolve spacing configuration.
---@param spacing integer|CsvView.Options.View.Spacing
---@param align_direction "right" | "left"
---@return integer left
---@return integer right
local function get_spacing(spacing, align_direction)
  if type(spacing) == "table" then
    return spacing.left or 0, spacing.right or 0
  end

  if type(spacing) == "number" then
    if align_direction == "right" then
      return spacing, 0
    else
      return 0, spacing
    end
  end

  error("`view.spacing` expected integer or table.")
end

--- create new view
---@param bufnr integer
---@param metrics CsvView.Metrics
---@param opts CsvView.InternalOptions
---@param header_lnum integer?
---@param on_dispose? fun()
---@return CsvView.View
function View:new(bufnr, metrics, opts, header_lnum, on_dispose)
  self.__index = self

  local obj = {}
  obj.bufnr = bufnr
  obj.metrics = metrics
  obj.opts = opts
  obj.header_lnum = header_lnum
  obj._extmarks = {}
  obj._on_dispose = on_dispose
  obj._locked = false

  return setmetatable(obj, self)
end

---
--- Render lines in the specified range.
---
--- This method checks if the lines are already rendered and renders them if not.
--- If you want to force re-rendering, use the `clear()` method before calling this method.
---
---@param top_lnum integer 1-indexed
---@param bot_lnum integer 1-indexed
function View:render_lines(top_lnum, bot_lnum)
  for lnum = top_lnum, bot_lnum do
    local ok, err = xpcall(self._render_line, util.wrap_stacktrace, self, lnum)
    if not ok then
      util.error_with_context(err, { lnum = lnum })
    end
  end
end

--- Display width of the first `count` columns, delimiters included.
---
--- Mirrors the padding rules of `_render_line`: each column occupies its width
--- plus the configured spacing, and every column is followed by a delimiter.
--- Returns nil while the metrics for those columns are still being computed.
---@param count integer number of columns, counted from the left
---@return integer? width
function View:pinned_width(count)
  local delimiter = (vim.b[self.bufnr].csvview_info or {}).delimiter ---@type { text: string }?
  if not delimiter then
    return nil
  end

  -- In border mode the delimiter is concealed by a single-cell border char.
  local delimiter_width = self.opts.view.display_mode == "border" and 1 or vim.fn.strdisplaywidth(delimiter.text)

  local spacing = self.opts.view.spacing
  local width = 0
  for column_index = 1, count do
    local column = self.metrics:column(column_index)
    if not column then
      return nil -- not computed yet, or fewer columns than requested
    end

    local left, right ---@type integer, integer
    if type(spacing) == "table" then
      left = column_index == 1 and 0 or (spacing.left or 0)
      right = spacing.right or 0
    else
      -- A number adds the same total spacing regardless of align direction.
      left, right = 0, spacing
    end

    width = width + math.max(column.max_width, self.opts.view.min_column_width) + left + right + delimiter_width
  end

  return width
end

--- Setup window options
--- @param winid integer
function View:setup_window(winid)
  -- Conceal delimiter-char if display_mode is border
  if self.opts.view.display_mode == "border" then
    set_local(winid, "concealcursor", "nvic")
    set_local(winid, "conceallevel", 2)
  end

  set_local(winid, "wrap", false)
end

--- Lock view rendering
function View:lock()
  self._locked = true
end

--- Unlock view rendering
function View:unlock()
  self._locked = false
end

--- check if view rendering is locked
---@return boolean
function View:is_locked()
  return self._locked
end

--- Clear all extmarks
function View:clear()
  for _, extmarks in pairs(self._extmarks) do
    for _, id in ipairs(extmarks) do
      vim.api.nvim_buf_del_extmark(self.bufnr, EXTMARK_NS, id)
    end
  end
  self._extmarks = {}
end

--- Dispose view
function View:dispose()
  self:clear()
  if self._on_dispose then
    self._on_dispose()
  end
end

-------------------------------------------------------
-- private methods
-------------------------------------------------------

--- Add extmark to buffer
---@param line integer 1-based lnum
---@param col integer 0-based column
---@param opts vim.api.keyset.set_extmark
function View:_add_extmark(line, col, opts)
  -- Manage extmark per line
  if not self._extmarks[line] then
    self._extmarks[line] = {}
  end

  self._extmarks[line][#self._extmarks[line] + 1] =
    vim.api.nvim_buf_set_extmark(self.bufnr, EXTMARK_NS, line - 1, col, opts)
end

--- Add virtual padding after the field text.
---@param lnum integer 1-indexed lnum
---@param col integer 0-based column
---@param padding integer
function View:_pad_after(lnum, col, padding)
  if padding <= 0 then
    return
  end

  self:_add_extmark(lnum, col, {
    virt_text = { { string.rep(" ", padding) } },
    virt_text_pos = "inline",
    right_gravity = true,
  })
end

--- Add virtual padding before the field text.
---@param lnum integer 1-indexed lnum
---@param col integer 0-based column
---@param padding integer
function View:_pad_before(lnum, col, padding)
  if padding <= 0 then
    return
  end

  self:_add_extmark(lnum, col, {
    virt_text = { { string.rep(" ", padding) } },
    virt_text_pos = "inline",
    right_gravity = false,
  })
end

--- Render delimiter char
---@param lnum integer 1-indexed lnum
---@param col integer 0-based start column
---@param end_col integer 0-based end column
function View:_render_delimiter(lnum, col, end_col)
  if self.opts.view.display_mode == "border" then
    self:_add_extmark(lnum, col, {
      hl_group = "CsvViewDelimiter",
      end_col = end_col,
      conceal = BORDER_CHAR,
    })
  else
    self:_add_extmark(lnum, col, {
      hl_group = "CsvViewDelimiter",
      end_col = end_col,
    })
  end
end

--- highlight comment line
---@param lnum integer 1-indexed lnum
function View:_highlight_comment(lnum)
  self:_add_extmark(lnum, 0, { hl_group = "CsvViewComment", end_row = lnum, hl_eol = true })
end

--- Check if line is already rendered
---@param lnum integer 1-indexed lnum
---@return boolean
function View:_already_rendered(lnum)
  return self._extmarks[lnum] and #self._extmarks[lnum] > 0
end

--- Render line
---@param lnum integer 1-indexed lnum
function View:_render_line(lnum)
  local store = self.metrics.store
  if not store:has_line(lnum) then
    return
  end
  local kind = store.kind[lnum]

  -- Do not render if already rendered.
  if self:_already_rendered(lnum) then
    return
  end

  if kind == KIND.COMMENT then
    self:_highlight_comment(lnum)
    return
  end

  -- highlight header
  if lnum == self.header_lnum then
    self:_add_extmark(lnum, 0, { line_hl_group = "CsvViewHeaderLine" })
  end

  -- Add padding for multiline continuation rows
  if kind == KIND.MULTILINE_CONTINUATION then
    local padlen = self:_calculate_padding_for_multiline(lnum, store.col0[lnum])
    self:_pad_before(lnum, 0, padlen)
  end

  -- The last field of an unterminated record is not highlighted.
  local unterminated_col = 0
  if kind ~= KIND.SINGLELINE and store.term[lnum] == 0 then
    local end_lnum = lnum + store.span[lnum]
    assert(store:has_line(end_lnum), "record end out of range")
    unterminated_col = store.col0[end_lnum] + store.count[end_lnum]
  end

  local view_opts = self.opts.view
  local min_width = view_opts.min_column_width
  local spacing = view_opts.spacing
  local spacing_is_table = type(spacing) == "table"
  local left_l, right_l = get_spacing(spacing, "left")
  local left_r, right_r = get_spacing(spacing, "right")

  local base, count, col0 = store.base[lnum], store.count[lnum], store.col0[lnum]
  for i = 0, count - 1 do
    local column_index = col0 + i + 1
    local column = self.metrics:column(column_index)
    if column then
      local idx = base + i
      local offset = store.off[idx]
      local end_col = offset + store.len[idx]

      -- Highlight column
      if column_index ~= unterminated_col then
        self:_add_extmark(lnum, offset, {
          hl_group = "CsvViewCol" .. (column_index - 1) % 9,
          end_col = end_col,
        })
      end

      -- Keep the delimiter position stable across rows by splitting padding into
      -- alignment padding and delimiter spacing.
      --
      -- `align_padding` is part of the column width. It goes before right-aligned
      -- fields and after left-aligned fields, so mixed number/text rows still end
      -- at the same delimiter column.
      --
      -- `spacing_left` represents the visual gap after the previous delimiter.
      -- The first field on a line has no previous delimiter, so table-style
      -- spacing should not add a leading gap there.
      local align_padding = math.max(column.max_width, min_width) - store.width[idx]
      local before_padding, after_padding ---@type integer, integer
      if store.num[idx] == 1 then
        before_padding, after_padding = left_r, right_r
      else
        before_padding, after_padding = left_l, right_l
      end
      if spacing_is_table and offset == 0 then
        before_padding = 0
      end
      if store.num[idx] == 1 then
        before_padding = before_padding + align_padding
      else
        after_padding = after_padding + align_padding
      end

      self:_pad_before(lnum, offset, before_padding)
      self:_pad_after(lnum, end_col, after_padding)

      -- if column is last, do not render delimiter
      if i + 1 < count then
        self:_render_delimiter(lnum, end_col, store.off[idx + 1])
      end
    end
  end
end

--- Calculate padding for multiline row
--- This is used to align multiline continuation rows with the first row.
--- @param lnum integer 1-indexed line number
--- @param skipped_ncol integer number of columns that start on previous lines of the record
--- @return integer padding
function View:_calculate_padding_for_multiline(lnum, skipped_ncol)
  local padding = 0
  local spacing_left, spacing_right = get_spacing(self.opts.view.spacing, "left")
  local ranges = self.metrics:get_logical_row_fields({ lnum = lnum })
  for i = skipped_ncol, 1, -1 do
    local column = self.metrics:column(i)
    if column then
      padding = padding + math.max(column.max_width, self.opts.view.min_column_width) + spacing_right
    end

    -- add padding for delimiters
    local range = ranges[i]
    local next_range = ranges[i + 1]
    if range and next_range then
      if self.opts.view.display_mode == "border" then
        padding = padding + vim.fn.strdisplaywidth(BORDER_CHAR)
      else
        local delimiter_text = vim.api.nvim_buf_get_text(
          self.bufnr,
          range.end_row - 1,
          range.end_col,
          next_range.start_row - 1,
          next_range.start_col,
          {}
        )[1]
        local delimiter_width = vim.fn.strdisplaywidth(delimiter_text)
        padding = padding + delimiter_width
      end
      padding = padding + spacing_left
    end
  end

  return padding
end

-------------------------------------------------------
-- module exports
-------------------------------------------------------

local M = {}

--- @type CsvView.View[]
M._views = {}

--- attach view for buffer
---@param bufnr integer
---@param view CsvView.View
function M.attach(bufnr, view)
  bufnr = util.resolve_bufnr(bufnr)
  if M._views[bufnr] then
    vim.notify("csvview: already attached for this buffer.")
    return
  end
  M._views[bufnr] = view

  -- Setup window options
  for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
    view:setup_window(winid)
  end
end

--- detach view for buffer
---@param bufnr integer
function M.detach(bufnr)
  bufnr = util.resolve_bufnr(bufnr)
  if not M._views[bufnr] then
    return
  end

  -- Dispose view
  local view = M._views[bufnr]
  M._views[bufnr] = nil
  view:dispose()
end

--- Get view for buffer
---@param bufnr integer
---@return CsvView.View?
function M.get(bufnr)
  bufnr = util.resolve_bufnr(bufnr)
  return M._views[bufnr]
end

M.View = View
return M
