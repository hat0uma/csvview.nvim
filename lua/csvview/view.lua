local EXTMARK_NS = vim.api.nvim_create_namespace("csv_extmark")

--- Get end column of line
---@param winid integer window id
---@param lnum integer 1-indexed lnum
---@return integer 0-indexed column
local function end_col(winid, lnum)
  ---@diagnostic disable-next-line: assign-type-mismatch
  return vim.fn.col({ lnum, "$" }, winid) - 1
end

--- @class CsvView
--- @field bufnr integer
--- @field metrics CsvViewMetrics
--- @field extmarks integer[]
--- @field opts CsvViewOptions
local CsvView = {}

--- create new view
---@param bufnr integer
---@param metrics CsvViewMetrics
---@param opts CsvViewOptions
---@return CsvView
function CsvView:new(bufnr, metrics, opts)
  self.__index = self

  local obj = {}
  obj.bufnr = bufnr
  obj.metrics = metrics
  obj.extmarks = {}
  obj.opts = opts
  return setmetatable(obj, self)
end

--- Align field to the left
---@param lnum integer 1-indexed lnum
---@param offset integer 0-indexed byte offset
---@param padding integer
---@param field CsvFieldMetrics.Field
---@param border boolean
function CsvView:_align_left(lnum, offset, padding, field, border)
  if padding > 0 then
    self.extmarks[#self.extmarks + 1] =
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
---@param field CsvFieldMetrics.Field
---@param border boolean
function CsvView:_align_right(lnum, offset, padding, field, border)
  if padding > 0 then
    self.extmarks[#self.extmarks + 1] = vim.api.nvim_buf_set_extmark(self.bufnr, EXTMARK_NS, lnum - 1, offset, {
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
function CsvView:render_column_index_header(lnum)
  local virt = {} --- @type string[][]
  for i, column in ipairs(self.metrics.columns) do
    local char = tostring(i)
    virt[#virt + 1] = { string.rep(" ", column.max_width - #char) }
    virt[#virt + 1] = { char }
    if i < #self.metrics.columns then
      virt[#virt + 1] = { "," }
    end
  end
  self.extmarks[#self.extmarks + 1] = vim.api.nvim_buf_set_extmark(self.bufnr, EXTMARK_NS, lnum - 1, 0, {
    virt_lines = { virt },
    virt_lines_above = true,
  })
end

--- highlight delimiter char
---@param lnum integer 1-indexed lnum
---@param offset integer 0-indexed byte offset
function CsvView:_highlight_delimiter(lnum, offset)
  self.extmarks[#self.extmarks + 1] = vim.api.nvim_buf_set_extmark(self.bufnr, EXTMARK_NS, lnum - 1, offset, {
    hl_group = "CsvViewDelimiter",
    end_col = offset + 1,
  })
end

--- render table border
---@param lnum integer 1-indexed lnum
---@param offset integer 0-indexed byte offset
function CsvView:_render_border(lnum, offset)
  self.extmarks[#self.extmarks + 1] = vim.api.nvim_buf_set_extmark(self.bufnr, EXTMARK_NS, lnum - 1, offset, {
    virt_text = { { "│", "CsvViewDelimiter" } },
    virt_text_pos = "overlay",
  })
end

--- clear view
function CsvView:clear()
  for _, id in pairs(self.extmarks) do
    vim.api.nvim_buf_del_extmark(self.bufnr, EXTMARK_NS, id)
  end
  self.extmarks = {}
end

--- render column
---@param lnum integer 1-indexed lnum
---@param column_index 1-indexed column index
---@param field CsvFieldMetrics.Field
---@param offset integer 0-indexed byte offset
function CsvView:render_column(lnum, column_index, field, offset)
  if not self.metrics.columns[column_index] then
    -- not computed yet.
    return
  end

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

--- render
---@param top_lnum integer 1-indexed
---@param bot_lnum integer 1-indexed
---@param winid integer window id
function CsvView:render(top_lnum, bot_lnum, winid)
  -- self:render_column_index_header(top_lnum)

  --- render all fields in ranges
  for lnum = top_lnum, bot_lnum do
    local line = self.metrics.rows[lnum]
    if not line then
      goto continue
    end

    if line.is_comment then
      -- highlight comment line
      self.extmarks[#self.extmarks + 1] = vim.api.nvim_buf_set_extmark(self.bufnr, EXTMARK_NS, lnum - 1, 0, {
        hl_group = "CsvViewComment",
        end_col = end_col(winid, lnum),
      })
      goto continue
    end

    local offset = 0
    for column_index, field in ipairs(line.fields) do
      self:render_column(lnum, column_index, field, offset)
      offset = offset + field.len + 1
    end
    ::continue::
  end
end

-------------------------------------------------------
-- module exports
-------------------------------------------------------

local M = {}

--- @type CsvView[]
M._views = {}

--- attach view for buffer
---@param bufnr integer
---@param metrics CsvViewMetrics
---@param opts CsvViewOptions
function M.attach(bufnr, metrics, opts)
  if M._views[bufnr] then
    vim.notify("csvview: already attached for this buffer.")
    return
  end
  M._views[bufnr] = CsvView:new(bufnr, metrics, opts)
  vim.cmd([[redraw!]])
end

--- detach view for buffer
---@param bufnr integer
function M.detach(bufnr)
  if not M._views[bufnr] then
    return
  end
  M._views[bufnr]:clear()
  M._views[bufnr].metrics:clear()
  M._views[bufnr] = nil
end

--- Get view for buffer
---@param bufnr integer
---@return CsvView?
function M.get(bufnr)
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

      -- do not rerender when in insert mode
      -- local m = vim.api.nvim_get_mode()
      -- if string.find(m["mode"], "i") then
      --   return false
      -- end

      -- clear last rendered.
      view:clear()

      -- render with current window range.
      local top = vim.fn.line("w0", winid)
      local bot = vim.fn.line("w$", winid)
      local ok, result = pcall(view.render, view, top, bot, winid)
      if not ok then
        vim.notify(string.format("csvview: error while rendering: %s", result), vim.log.levels.ERROR)
        M.detach(bufnr)
      end

      return false
    end,
  })
end

M.CsvView = CsvView
return M
