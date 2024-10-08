local M = {}
local EXTMARK_NS = vim.api.nvim_create_namespace("csv_extmark")

--- @class CsvView
--- @field bufnr integer
--- @field fields CsvFieldMetrics[][]
--- @field column_max_widths integer[]
--- @field extmarks integer[]
--- @field opts CsvViewOptions
local CsvView = {}

--- create new view
---@param bufnr integer
---@param fields CsvFieldMetrics[][]
---@param column_max_widths integer[]
---@param opts CsvViewOptions
---@return CsvView
function CsvView:new(bufnr, fields, column_max_widths, opts)
  self.__index = self

  local obj = {}
  obj.bufnr = bufnr
  obj.fields = fields
  obj.column_max_widths = column_max_widths
  obj.extmarks = {}
  obj.opts = opts
  return setmetatable(obj, self)
end

--- Align field to the left
---@param lnum integer 1-indexed lnum
---@param offset integer 0-indexed byte offset
---@param padding integer
---@param field CsvFieldMetrics
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
---@param field CsvFieldMetrics
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
  for i, width in ipairs(self.column_max_widths) do
    local char = tostring(i)
    virt[#virt + 1] = { string.rep(" ", width - #char) }
    virt[#virt + 1] = { char }
    if i < #self.column_max_widths then
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
---@param field CsvFieldMetrics
---@param offset integer 0-indexed byte offset
function CsvView:render_column(lnum, column_index, field, offset)
  if not self.column_max_widths[column_index] then
    -- column_max_widths is not computed yet.
    return
  end
  -- if column is last, do not render border.
  local render_border = column_index < #self.fields[lnum]
  local colwidth = math.max(self.column_max_widths[column_index], self.opts.view.min_column_width)
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
function CsvView:render(top_lnum, bot_lnum)
  -- self:render_column_index_header(top_lnum)

  --- render all fields in ranges
  for lnum = top_lnum, bot_lnum do
    local line = self.fields[lnum]
    if not line then
      goto continue
    end

    local offset = 0
    for column_index, field in ipairs(line) do
      self:render_column(lnum, column_index, field, offset)
      offset = offset + field.len + 1
    end
    ::continue::
  end
end

--- update item
---@param fields CsvFieldMetrics[][]
---@param column_max_widths integer[]
function CsvView:update(fields, column_max_widths)
  self.fields = fields
  self.column_max_widths = column_max_widths
end

--- @type CsvView[]
M._views = {}

--- attach view for buffer
---@param bufnr integer
---@param fields CsvFieldMetrics[][] }
---@param column_max_widths number[]
---@param opts CsvViewOptions
function M.attach(bufnr, fields, column_max_widths, opts)
  if M._views[bufnr] then
    vim.notify("csvview: already attached for this buffer.")
    return
  end
  M._views[bufnr] = CsvView:new(bufnr, fields, column_max_widths, opts)
  vim.cmd([[redraw!]])
end

--- detach view for buffer
---@param bufnr integer
function M.detach(bufnr)
  if not M._views[bufnr] then
    return
  end
  M._views[bufnr]:clear()
  M._views[bufnr] = nil
end

--- start render
---@param bufnr integer
---@param fields CsvFieldMetrics[][] }
---@param column_max_widths number[]
function M.update(bufnr, fields, column_max_widths)
  if not M._views[bufnr] then
    return
  end
  M._views[bufnr]:update(fields, column_max_widths)
  vim.cmd([[redraw!]])
end

--- setup view
function M.setup()
  -- set highlight
  vim.api.nvim_set_hl(0, "CsvViewDelimiter", { link = "Comment", default = true })

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
      local ok, result = pcall(view.render, view, top, bot)
      if not ok then
        vim.notify(string.format("csvview: error while rendering: %s", result), vim.log.levels.ERROR)
        view:clear()
        view.column_max_widths = {}
        view.fields = {}
      end

      return false
    end,
  })
end

M.CsvView = CsvView
return M
