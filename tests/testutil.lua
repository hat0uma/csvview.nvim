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

local FEEDKEYS_DONE_KEY = "<Plug>(csvview-test-feedkeys-done)"

--- Feed keys as if typed by the user, and wait until they are processed.
---
--- `nvim_feedkeys(keys, "x")` cannot be used here because keys executed that way
--- never reach the main loop, so the multicursor cascade is not replayed.
--- (see `:h multicursor`)
---@async
---@param thread thread
---@param keys string keys in `:h key-notation`
function M.feedkeys(thread, keys)
  local done = false
  vim.keymap.set("n", FEEDKEYS_DONE_KEY, function()
    done = true
  end)

  -- The marker key is processed after all the keys before it, including the cascade.
  vim.api.nvim_feedkeys(vim.keycode(keys) .. vim.keycode(FEEDKEYS_DONE_KEY), "t", false)

  local wait_ms = 0
  while not done and wait_ms < 5000 do
    vim.defer_fn(function()
      coroutine.resume(thread)
    end, 10)
    coroutine.yield()
    wait_ms = wait_ms + 10
  end

  vim.keymap.del("n", FEEDKEYS_DONE_KEY)
  if not done then
    error(string.format("testutil.feedkeys: timed out while processing keys '%s'", keys))
  end
end

--- Get the positions of the multicursors in the buffer.
---@param bufnr integer
---@return [integer,integer][] positions 1-based line number and 0-based byte offset
function M.get_multicursors(bufnr)
  local ns = vim.api.nvim_create_namespace("nvim.multicursor")
  local positions = {} ---@type [integer,integer][]
  for _, extmark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})) do
    table.insert(positions, { extmark[2] + 1, extmark[3] })
  end
  return positions
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
