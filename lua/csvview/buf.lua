--- Buffer utilities
local M = {}

--- Resolve bufnr
---@param bufnr integer| nil
---@return integer
function M.resolve_bufnr(bufnr)
  if not bufnr or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  else
    return bufnr
  end
end

--- Get buffer attached window
---@param bufnr integer
---@return integer?
function M.get_win(bufnr)
  -- Prefer current window
  local current_win = vim.api.nvim_get_current_win()
  local current_buf = vim.api.nvim_win_get_buf(current_win)
  if current_buf == bufnr then
    return current_win
  end

  -- Find window
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == bufnr then
      return winid
    end
  end
  return nil
end

--- Watch buffer-update events
---@param bufnr integer
---@param callbacks vim.api.keyset.buf_attach
---@return fun() detach_bufevent
function M.attach(bufnr, callbacks)
  local detached = false
  local function wrap_buf_attach_handler(cb)
    if not cb then
      return nil
    end

    return function(...)
      if detached then
        return true -- detach
      end

      return cb(...)
    end
  end

  local function attach_events()
    vim.api.nvim_buf_attach(bufnr, false, {
      on_lines = wrap_buf_attach_handler(callbacks.on_lines),
      on_bytes = wrap_buf_attach_handler(callbacks.on_bytes),
      on_changedtick = wrap_buf_attach_handler(callbacks.on_changedtick),
      on_reload = wrap_buf_attach_handler(callbacks.on_reload),
      on_detach = wrap_buf_attach_handler(callbacks.on_detach),
      preview = true, -- for inccommand
    })
  end

  -- Attach to buffer
  attach_events()

  -- Re-register events on `:e`
  local buf_event_auid = vim.api.nvim_create_autocmd({ "BufReadPost" }, {
    callback = function()
      attach_events()
      if callbacks.on_reload then
        callbacks.on_reload("reload", bufnr)
      end
    end,
    buffer = bufnr,
  })

  -- detach
  return function()
    if detached then
      return
    end

    vim.api.nvim_del_autocmd(buf_event_auid)
    detached = true
  end
end

return M
