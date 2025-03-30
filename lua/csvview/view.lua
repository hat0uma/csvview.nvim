local EXTMARK_NS = vim.api.nvim_create_namespace("csv_extmark")
local buf = require("csvview.buf")
local config = require("csvview.config")
local errors = require("csvview.errors")

--- @class CsvView.View
--- @field public bufnr integer
--- @field public metrics CsvView.Metrics
--- @field public opts CsvView.InternalOptions
--- @field private _extmarks table<integer,integer[]> 1-based line -> extmark ids
--- @field private _on_dispose function? called when view is disposed
--- @field private _locked boolean
--- @field private _delimiter string
local View = {}

--- create new view
---@param bufnr integer
---@param metrics CsvView.Metrics
---@param opts CsvView.InternalOptions
---@param on_dispose? fun()
---@return CsvView.View
function View:new(bufnr, metrics, opts, on_dispose)
  self.__index = self

  local obj = {}
  obj.bufnr = bufnr
  obj.metrics = metrics
  obj.opts = opts
  obj._extmarks = {}
  obj._on_dispose = on_dispose
  obj._locked = false
  obj._delimiter = config.resolve_delimiter(opts, bufnr)
  return setmetatable(obj, self)
end

--- Render view
---@param force? boolean force render even if locked
function View:render(force)
  if not force and self:is_locked() then
    return
  end

  -- Clear previous rendering before re-render
  self:clear()

  -- Render with all window ranges
  local wins = buf.tabpage_win_find(0, self.bufnr)
  for _, winid in ipairs(wins) do
    local top = vim.fn.line("w0", winid)
    local bot = vim.fn.line("w$", winid)

    self:_set_window_options(winid)
    self:_render_lines(top, bot)
  end
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

--- Align field to the left
---@param lnum integer 1-indexed lnum
---@param offset integer 0-indexed byte offset
---@param padding integer
---@param field CsvView.Metrics.Field
function View:_align_field(lnum, offset, padding, field)
  if padding <= 0 then
    return
  end

  local pad = { { string.rep(" ", padding) } }
  if field.is_number then
    -- align right
    self:_add_extmark(lnum, offset, {
      virt_text = pad,
      virt_text_pos = "inline",
      right_gravity = false,
    })
  else
    -- align left
    self:_add_extmark(lnum, offset + field.len, {
      virt_text = pad,
      virt_text_pos = "inline",
      right_gravity = true,
    })
  end
end

--- Render delimiter char
---@param lnum integer 1-indexed lnum
---@param offset integer 0-indexed byte offset
function View:_render_delimiter(lnum, offset)
  local end_col = offset + #self._delimiter
  if self.opts.view.display_mode == "border" then
    self:_add_extmark(lnum, offset, {
      hl_group = "CsvViewDelimiter",
      end_col = end_col,
      conceal = "│",
    })
  else
    self:_add_extmark(lnum, offset, {
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

--- highlight field
---@param lnum integer 1-indexed lnum
---@param column_index integer 1-indexed column index
---@param offset integer 0-indexed byte offset
---@param field CsvView.Metrics.Field
function View:_highlight_field(lnum, column_index, offset, field)
  -- highlight field
  self:_add_extmark(lnum, offset, {
    hl_group = "CsvViewCol" .. (column_index - 1) % 9,
    end_col = offset + field.len,
  })

  -- highlight header
  -- The array format of hl_group is not supported in neovim 0.10, so the header line highlight is separate.
  if lnum == self.opts.view.header_lnum then
    self:_add_extmark(lnum, offset, {
      hl_group = "CsvViewHeader",
      end_col = offset + field.len,
    })
  end
end

--- Render field in line
---@param lnum integer 1-indexed lnum
---@param column_index 1-indexed column index
---@param field CsvView.Metrics.Field
---@param offset integer 0-indexed byte offset
function View:_render_field(lnum, column_index, field, offset)
  if not self.metrics.columns[column_index] then
    -- not computed yet.
    return
  end

  -- if column is last, do not render delimiter
  local should_render_delimiter = column_index < #self.metrics.rows[lnum].fields
  local colwidth = math.max(self.metrics.columns[column_index].max_width, self.opts.view.min_column_width)
  local padding = colwidth - field.display_width + self.opts.view.spacing

  self:_highlight_field(lnum, column_index, offset, field)
  self:_align_field(lnum, offset, padding, field)
  if should_render_delimiter then
    self:_render_delimiter(lnum, offset + field.len)
  end
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
  local line = self.metrics.rows[lnum]
  if not line then
    return
  end

  -- Do not render if already rendered.
  -- Another window may have already rendered this line.
  if self:_already_rendered(lnum) then
    return
  end

  if line.is_comment then
    self:_highlight_comment(lnum)
    return
  end

  -- render fields
  local offset = 0
  for column_index, field in ipairs(line.fields) do
    local ok, err = xpcall(self._render_field, errors.wrap_stacktrace, self, lnum, column_index, field, offset)
    if not ok then
      errors.error_with_context(err, { lnum = lnum, column_index = column_index })
    end
    offset = offset + field.len + #self._delimiter
  end
end

--- Set window options for view
--- `:h nvim_set_decoration_provider()` says that setting options inside the callback can lead to unexpected results.
--- Therefore, it is set to be executed in the next tick using `vim.schedule_wrap()`.
---@type fun(self:CsvView.View, winid:integer )
View._set_window_options = vim.schedule_wrap(
  --- @param self CsvView.View
  --- @param winid integer
  function(self, winid)
    if not vim.api.nvim_win_is_valid(winid) then
      return
    end

    local function set_local(key, value)
      if vim.api.nvim_get_option_value(key, { scope = "local", win = winid }) ~= value then
        vim.api.nvim_set_option_value(key, value, { scope = "local", win = winid })
      end
    end

    if self.opts.view.display_mode == "border" then
      -- Settings for conceal delimiter with border
      set_local("concealcursor", "nvic")
      set_local("conceallevel", 2)
    end
  end
)

--- Render lines
---@param top_lnum integer 1-indexed
---@param bot_lnum integer 1-indexed
function View:_render_lines(top_lnum, bot_lnum)
  for lnum = top_lnum, bot_lnum do
    local ok, err = xpcall(self._render_line, errors.wrap_stacktrace, self, lnum)
    if not ok then
      errors.error_with_context(err, { lnum = lnum })
    end
  end
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
  bufnr = buf.resolve_bufnr(bufnr)
  if M._views[bufnr] then
    vim.notify("csvview: already attached for this buffer.")
    return
  end
  M._views[bufnr] = view
  vim.cmd([[redraw!]])
end

--- detach view for buffer
---@param bufnr integer
function M.detach(bufnr)
  bufnr = buf.resolve_bufnr(bufnr)
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
  bufnr = buf.resolve_bufnr(bufnr)
  return M._views[bufnr]
end

--- Render all views
function M.render()
  for _, view in pairs(M._views) do
    local ok, err = xpcall(view.render, errors.wrap_stacktrace, view)
    if not ok then
      errors.print_structured_error("CsvView Rendering Stopped with Error", err)
      M.detach(view.bufnr)
    end
  end
end

--- setup view
function M.setup()
  vim.api.nvim_set_decoration_provider(EXTMARK_NS, {
    on_start = function(_, _)
      M.render()
      return false
    end,
  })
end

M.View = View
return M
