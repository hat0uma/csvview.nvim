local M = {}

---@class CsvView.BufferEvents
---@field on_lines fun(event: "lines", bufnr: integer, changedtick: integer, first: integer, last: integer, last_updated: integer, byte_count: integer, deleted_codepoints: integer, deleted_codeunits: integer): boolean | nil Return `true` to detach from buffer events.
---@field on_reload fun(event: "reload", bufnr: integer) : boolean | nil Return `true` to detach from buffer events.

---Register buffer events. This will attach to the buffer and listen for events.
---When the buffer is reloaded, the events will be re-registered.
---@param bufnr integer
---@param events CsvView.BufferEvents
function M.register(bufnr, events)
  -- Re-register events on `:e`
  vim.b[bufnr].csvview_update_auid = vim.api.nvim_create_autocmd({ "BufReadPost" }, {
    callback = function()
      M.register(bufnr, events)
      events.on_reload("reload", bufnr)
    end,
    buffer = bufnr,
    once = true,
  })

  -- Attach to buffer
  vim.api.nvim_buf_attach(bufnr, false, {
    on_lines = function(...)
      return events.on_lines(...)
    end,
    on_reload = function(...)
      return events.on_reload(...)
    end,
  })
end

---Unregister buffer events.
---This will detach from the buffer and stop listening for events.
---@param bufnr integer
function M.unregister(bufnr)
  vim.api.nvim_del_autocmd(vim.b[bufnr].csvview_update_auid)
  vim.b[bufnr].csvview_update_auid = nil
end

return M
