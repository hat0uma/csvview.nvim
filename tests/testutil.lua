local M = {}

--- Get lines extmarks applied
---@param bufnr integer
---@param ns integer
---@return string[]
function M.get_lines_with_extmarks(bufnr, ns)
  -- get lines and extmarks
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
  local col_offset = {} --- @type integer[]
  for _, extmark in ipairs(extmarks) do
    local row = extmark[2] --- @type integer
    local col = extmark[3] --- @type integer
    local details = extmark[4] --- @type { virt_text: string[][]?, virt_text_pos: string? }
    local lnum = row + 1
    if details.virt_text_pos == "inline" then
      for _, virt_text in pairs(details.virt_text) do
        col_offset[lnum] = col_offset[lnum] or 0
        local prefix = lines[lnum]:sub(0, col + col_offset[lnum])
        local suffix = lines[lnum]:sub(col + col_offset[lnum] + 1)
        lines[lnum] = prefix .. virt_text[1] .. suffix
        col_offset[lnum] = col_offset[lnum] + #virt_text[1]
      end
    elseif details.virt_text_pos == "overlay" then
      local virt_text = details.virt_text[1][1]
      col_offset[lnum] = col_offset[lnum] or 0
      local prefix = lines[lnum]:sub(1, col + col_offset[lnum])
      local suffix = lines[lnum]:sub(col + col_offset[lnum] + 1 + vim.fn.strdisplaywidth(virt_text))
      lines[lnum] = prefix .. virt_text .. suffix
      col_offset[lnum] = col_offset[lnum] + #virt_text - vim.fn.strdisplaywidth(virt_text)
    end
  end

  return lines
end

---@async
---@param thread thread
function M.yield_next_loop(thread)
  vim.schedule(function()
    coroutine.resume(thread)
  end)
  coroutine.yield()
end

return M
