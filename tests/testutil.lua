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
    local details = extmark[4] --- @type vim.api.keyset.extmark_details
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
    elseif details.conceal ~= nil then
      local conceal = details.conceal
      local end_col = details.end_col
      col_offset[lnum] = col_offset[lnum] or 0
      local prefix = lines[lnum]:sub(1, col + col_offset[lnum])
      local suffix = lines[lnum]:sub(end_col + col_offset[lnum] + 1)
      lines[lnum] = prefix .. conceal .. suffix
      col_offset[lnum] = col_offset[lnum] + #conceal - (end_col - col)
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

--- Read lines from a file and return them as a table.
---@param filename string
---@return string[]
function M.readlines(filename)
  local err, err_msg ---@type string?, string?

  local f
  f, err, err_msg = vim.uv.fs_open(filename, "r", 438) -- 0666
  if not f then
    error(string.format("Failed to open file '%s': %s", filename, err_msg or err))
  end

  local stat
  stat, err, err_msg = vim.uv.fs_fstat(f)
  if not stat then
    vim.uv.fs_close(f)
    error(string.format("Failed to stat file '%s': %s", filename, err_msg or err))
  end

  if stat.type ~= "file" then
    vim.uv.fs_close(f)
    error(string.format("Expected a file, but got: %s", stat.type))
  end

  local text
  text, err, err_msg = vim.uv.fs_read(f, stat.size)
  if not text then
    vim.uv.fs_close(f)
    error(string.format("Failed to read file '%s': %s", filename, err_msg or err))
  end

  vim.uv.fs_close(f)
  return vim.split(vim.trim(text), "\n", { plain = true })
end

return M
