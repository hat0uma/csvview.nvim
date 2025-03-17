local EXTMARK_NS = vim.api.nvim_create_namespace("csv_extmark")
local buf = require("csvview.buf")
local config = require("csvview.config")
local errors = require("csvview.errors")

--- Get end column of line
---@param winid integer window id
---@param lnum integer 1-indexed lnum
---@return integer 0-indexed column
local function end_col(winid, lnum)
  ---@diagnostic disable-next-line: assign-type-mismatch
  return vim.fn.col({ lnum, "$" }, winid) - 1
end

--- @class CsvView.View
--- @field public bufnr integer
--- @field public metrics CsvView.Metrics
--- @field public opts CsvView.InternalOptions
--- @field private _extmarks integer[]
--- @field private _on_dispose function?
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

--- Align field to the left
---@param lnum integer 1-indexed lnum
---@param offset integer 0-indexed byte offset
---@param padding integer
---@param field CsvView.Metrics.Field
---@param border boolean
function View:_align_left(lnum, offset, padding, field, border)
  if padding > 0 then
    self._extmarks[#self._extmarks + 1] =
      vim.api.nvim_buf_set_extmark(self.bufnr, EXTMARK_NS, lnum - 1, offset + field.len, {
        virt_text = { { string.rep(" ", padding) } },
        virt_text_pos = "inline",
        right_gravity = true,
      })
  end

  if not border then
    return
  end

  -- render border or highlight delimiter
  if self.opts.view.display_mode == "border" then
    self:_render_border(lnum, offset + field.len)
  else
    self:_highlight_delimiter(lnum, offset + field.len)
  end
end

--- Align field to the right
---@param lnum integer 1-indexed lnum
---@param offset integer 0-indexed byte offset
---@param padding integer
---@param field CsvView.Metrics.Field
---@param border boolean
function View:_align_right(lnum, offset, padding, field, border)
  if padding > 0 then
    self._extmarks[#self._extmarks + 1] = vim.api.nvim_buf_set_extmark(self.bufnr, EXTMARK_NS, lnum - 1, offset, {
      virt_text = { { string.rep(" ", padding) } },
      virt_text_pos = "inline",
      right_gravity = false,
    })
  end

  if not border then
    return
  end

  -- render border or highlight delimiter
  if self.opts.view.display_mode == "border" then
    self:_render_border(lnum, offset + field.len)
  else
    self:_highlight_delimiter(lnum, offset + field.len)
  end
end

--- render column index header
---@param lnum integer 1-indexed lnum.render header above this line.
function View:render_column_index_header(lnum)
  local virt = {} --- @type string[][]
  for i, column in ipairs(self.metrics.columns) do
    local char = tostring(i)
    virt[#virt + 1] = { string.rep(" ", column.max_width - #char + self.opts.view.spacing) }
    virt[#virt + 1] = { char }
    if i < #self.metrics.columns then
      virt[#virt + 1] = { "," }
    end
  end
  self._extmarks[#self._extmarks + 1] = vim.api.nvim_buf_set_extmark(self.bufnr, EXTMARK_NS, lnum - 1, 0, {
    virt_lines = { virt },
    virt_lines_above = true,
  })
end

--- highlight delimiter char
---@param lnum integer 1-indexed lnum
---@param offset integer 0-indexed byte offset
function View:_highlight_delimiter(lnum, offset)
  self._extmarks[#self._extmarks + 1] = vim.api.nvim_buf_set_extmark(self.bufnr, EXTMARK_NS, lnum - 1, offset, {
    hl_group = "CsvViewDelimiter",
    end_col = offset + #self._delimiter,
  })
end

--- highlight field
---@param lnum integer 1-indexed lnum
---@param column_index integer 1-indexed column index
---@param offset integer 0-indexed byte offset
---@param field CsvView.Metrics.Field
function View:_highlight_field(lnum, column_index, offset, field)
  -- use built-in csv syntax highlight group.
  -- csvCol0 ~ csvCol8
  -- see https://github.com/neovim/neovim/blob/master/runtime/syntax/csv.vim
  local hl_group = "csvCol" .. (column_index - 1) % 9
  self._extmarks[#self._extmarks + 1] = vim.api.nvim_buf_set_extmark(self.bufnr, EXTMARK_NS, lnum - 1, offset, {
    hl_group = hl_group,
    end_col = offset + field.len,
  })
end

--- render table border
---@param lnum integer 1-indexed lnum
---@param offset integer 0-indexed byte offset
function View:_render_border(lnum, offset)
  self._extmarks[#self._extmarks + 1] = vim.api.nvim_buf_set_extmark(self.bufnr, EXTMARK_NS, lnum - 1, offset, {
    conceal = "│",
    end_col = offset + #self._delimiter,
    hl_group = "CsvViewDelimiter",
  })
end

--- clear view
function View:clear()
  for _ = 1, #self._extmarks do
    local id = table.remove(self._extmarks)
    vim.api.nvim_buf_del_extmark(self.bufnr, EXTMARK_NS, id)
  end
end

function View:dispose()
  self:clear()
  if self._on_dispose then
    self._on_dispose()
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

  self:_highlight_field(lnum, column_index, offset, field)

  -- if column is last, do not render border.
  local render_border = column_index < #self.metrics.rows[lnum].fields
  local colwidth = math.max(self.metrics.columns[column_index].max_width, self.opts.view.min_column_width)
  local padding = colwidth - field.display_width + self.opts.view.spacing
  if field.is_number then
    self:_align_right(lnum, offset, padding, field, render_border)
  else
    self:_align_left(lnum, offset, padding, field, render_border)
  end
end

--- Render line
---@param lnum integer 1-indexed lnum
---@param winid integer window id
function View:_render_line(lnum, winid)
  local line = self.metrics.rows[lnum]
  if not line then
    return
  end

  if line.is_comment then
    -- highlight comment line
    self._extmarks[#self._extmarks + 1] = vim.api.nvim_buf_set_extmark(self.bufnr, EXTMARK_NS, lnum - 1, 0, {
      hl_group = "CsvViewComment",
      end_col = end_col(winid, lnum),
    })
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

--- Render view
---@param top_lnum integer 1-indexed
---@param bot_lnum integer 1-indexed
---@param winid integer window id
function View:render(top_lnum, bot_lnum, winid)
  -- https://github.com/neovim/neovim/issues/16166
  -- self:render_column_index_header(top_lnum)

  -- set conceal for display_mode="border"
  if self.opts.view.display_mode == "border" then
    vim.api.nvim_win_call(winid, function()
      vim.wo[winid][0].concealcursor = "nvic"
      vim.wo[winid][0].conceallevel = 2
    end)
  end

  --- render all fields in ranges
  for lnum = top_lnum, bot_lnum do
    local ok, err = xpcall(self._render_line, errors.wrap_stacktrace, self, lnum, winid)
    if not ok then
      errors.error_with_context(err, { lnum = lnum })
    end
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
  M._views[bufnr]:dispose()
  M._views[bufnr] = nil
end

--- Get view for buffer
---@param bufnr integer
---@return CsvView.View?
function M.get(bufnr)
  bufnr = buf.resolve_bufnr(bufnr)
  return M._views[bufnr]
end

--- setup view
function M.setup()
  -- set highlight
  vim.api.nvim_set_hl(0, "CsvViewDelimiter", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "CsvViewComment", { link = "Comment", default = true })

  -- set decorator
  vim.api.nvim_set_decoration_provider(EXTMARK_NS, {
    on_win = function(_, winid, bufnr, _, _)
      local view = M._views[bufnr]
      if not view then
        return false
      end

      -- do not render when locked
      if view:is_locked() then
        return false
      end

      -- clear last rendered.
      view:clear()

      -- render with current window range.
      local top = vim.fn.line("w0", winid)
      local bot = vim.fn.line("w$", winid)
      local ok, err = xpcall(view.render, errors.wrap_stacktrace, view, top, bot, winid)
      if not ok then
        errors.print_structured_error("CsvView Rendering Stopped with Error", err)
        M.detach(bufnr)
      end

      return false
    end,
  })
end

M.View = View
return M
