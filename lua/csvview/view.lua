local M = {}
local EXTMARK_NS = vim.api.nvim_create_namespace("csv_extmark")

local config = {
  min_column_width = 5,
  pack = 2,
  border = {
    char = "│",
    hl = "Comment",
  },
}
--- @class CsvView
--- @field bufnr integer
--- @field fields CsvFieldMetrics[][]
--- @field column_max_widths integer[]
--- @field extmarks integer[]
local CsvView = {}

--- create new view
---@param bufnr integer
---@param fields CsvFieldMetrics[][]
---@param column_max_widths integer[]
---@return CsvView
function CsvView:new(bufnr, fields, column_max_widths)
  self.__index = self

  local obj = {}
  obj.bufnr = bufnr
  obj.fields = fields
  obj.column_max_widths = column_max_widths
  obj.extmarks = {}
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

  if border then
    -- self:_render_border(lnum, offset + field.len, padding)
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

  if border then
    -- self:_render_border(lnum, offset + field.len, 0)
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
    hl_group = config.border.hl,
    end_col = offset + 1,
  })
end

--- render table border
---@param lnum integer 1-indexed lnum
---@param offset integer 0-indexed byte offset
---@param padding integer
function CsvView:_render_border(lnum, offset, padding)
  self.extmarks[#self.extmarks + 1] = vim.api.nvim_buf_set_extmark(self.bufnr, EXTMARK_NS, lnum - 1, offset, {
    virt_text = { { string.rep(" ", padding) .. config.border.char, config.border.hl } },
    virt_text_pos = "overlay",
  })
end

--- get column width
---@param column_index integer 1-indexed
---@return integer
function CsvView:_colwidth(column_index)
  return math.max(self.column_max_widths[column_index], config.min_column_width)
end

--- clear view
function CsvView:clear()
  for _, id in pairs(self.extmarks) do
    vim.api.nvim_buf_del_extmark(self.bufnr, EXTMARK_NS, id)
  end
  self.extmarks = {}
end

--- render
---@param top_lnum integer 1-indexed
---@param bot_lnum integer 1-indexed
function CsvView:render(top_lnum, bot_lnum)
  -- clear last rendered.
  self:clear()

  -- self:render_column_index_header(top_lnum)
  --- render all fields in ranges
  for lnum = top_lnum, bot_lnum do
    if self.fields[lnum] == nil then
      goto continue
    end
    local offset = 0
    for column_index, field in ipairs(self.fields[lnum]) do
      local padding = self:_colwidth(column_index) - field.display_width + config.pack
      local render_border = column_index < #self.fields[lnum]
      if field.is_number then
        self:_align_right(lnum, offset, padding, field, render_border)
      else
        self:_align_left(lnum, offset, padding, field, render_border)
      end
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
local views = {}

--- attach view for buffer
---@param bufnr integer
---@param fields CsvFieldMetrics[][] }
---@param column_max_widths number[]
function M.attach(bufnr, fields, column_max_widths)
  if views[bufnr] then
    print("csvview is already attached for this buffer.")
    return
  end
  views[bufnr] = CsvView:new(bufnr, fields, column_max_widths)
end

--- detach view for buffer
---@param bufnr integer
function M.detach(bufnr)
  if not views[bufnr] then
    print("csvview is not attached for this buffer.")
    return
  end
  views[bufnr]:clear()
  views[bufnr] = nil
end

--- start render
---@param bufnr integer
---@param fields CsvFieldMetrics[][] }
---@param column_max_widths number[]
function M.update(bufnr, fields, column_max_widths)
  if not views[bufnr] then
    print("csvview is not attached for this buffer.")
    return
  end
  views[bufnr]:update(fields, column_max_widths)
end

--- setup view
function M.setup()
  vim.api.nvim_set_decoration_provider(EXTMARK_NS, {
    on_win = function(_, winid, bufnr, _, _)
      if not views[bufnr] then
        return false
      end

      -- do not rerender when in insert mode
      -- local m = vim.api.nvim_get_mode()
      -- if string.find(m["mode"], "i") then
      --   return false
      -- end

      local top = vim.fn.line("w0", winid)
      local bot = vim.fn.line("w$", winid)
      views[bufnr]:render(top, bot)
      return false
    end,
  })
end

return M
