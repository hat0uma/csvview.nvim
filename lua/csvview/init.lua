local M = {}

local CsvView = require("csvview.view").View
local sticky_header = require("csvview.sticky_header")
local views = require("csvview.view")

local CsvViewMetrics = require("csvview.metrics")
local buf = require("csvview.buf")
local config = require("csvview.config")
local keymap = require("csvview.keymap")

--- check if csv table view is enabled
---@param bufnr integer
---@return boolean
function M.is_enabled(bufnr)
  bufnr = buf.resolve_bufnr(bufnr)
  return views.get(bufnr) ~= nil
end

--- enable csv table view
---@param bufnr integer?
---@param opts CsvView.Options?
function M.enable(bufnr, opts)
  bufnr = buf.resolve_bufnr(bufnr)
  opts = config.get(opts) ---@diagnostic disable-line: cast-local-type

  if M.is_enabled(bufnr) then
    vim.notify("csvview: already enabled for this buffer.")
    return
  end

  -- Create a new CsvView instance
  local on_detach --- @type fun()
  local metrics = CsvViewMetrics:new(bufnr, opts)
  local view = CsvView:new(bufnr, metrics, opts, function() -- on detach
    on_detach()
  end)

  -- Register buffer-update events.
  local detach_bufevent_handle = buf.attach(bufnr, {
    on_lines = function(_, _, changedtick, first, last, last_updated)
      if changedtick == vim.NIL then
        -- Handle update preview with inccommand
        -- Temporarily disable tabular view when updates are made with `inccommand`
        view:clear()
        view:lock()

        -- Resume table view when `inccommand` ends
        -- NOTE: A normal buffer update event occurs if the preview changes are accepted,
        -- but if canceled, no buffer update event occurs, so unlock on CmdlineLeave event
        vim.api.nvim_create_autocmd("CmdlineLeave", {
          callback = function()
            view:unlock()
          end,
          once = true,
        })
      else
        -- Handle normal buffer update events
        -- TODO: Process the case where the next update comes before the current update is completed
        metrics:update(first, last, last_updated, function()
          view:render()

          -- Re-render the view in next event loop
          -- NOTE: This is a workaround for the problem that when nvim_buf_attach's `on_lines` is triggered by `undo`,
          -- calling `nvim_buf_set_extmark` sets the extmark to the position before undo.
          vim.schedule(function()
            view:render()
          end)
        end)
      end
    end,
    on_reload = function()
      -- Clear and recompute metrics when buffer is reloaded
      view:clear()
      metrics:clear()
      view:lock()
      metrics:compute_buffer(function()
        view:unlock()
      end)
    end,
  })

  -- Define augroup
  -- Disable csvview when buffer is unloaded
  local group = vim.api.nvim_create_augroup("csvview", { clear = false })
  vim.api.nvim_clear_autocmds({ group = group, buffer = bufnr })
  vim.api.nvim_create_autocmd("BufUnload", {
    callback = function()
      if M.is_enabled(bufnr) then
        M.disable(bufnr)
      end
    end,
    group = group,
    desc = "csvview: disable when buffer is unloaded",
    buffer = bufnr,
  })

  local orig_syntax = vim.bo[bufnr].syntax

  -- Register detach callback
  on_detach = function()
    vim.api.nvim_clear_autocmds({ group = group, buffer = bufnr })
    detach_bufevent_handle()
    metrics:clear()
    keymap.unregister(opts)
    sticky_header.redraw()
    vim.bo[bufnr].syntax = orig_syntax
    vim.api.nvim_exec_autocmds("User", { pattern = "CsvViewDetach", data = bufnr })
  end

  -- Calculate metrics and attach view.
  metrics:compute_buffer(function()
    -- disable builtin syntax highlighting.
    -- NOTE: This is necessary to prevent syntax highlighting from interfering with the custom highlighting of the view.
    vim.bo[bufnr].syntax = ""

    keymap.register(opts)
    views.attach(bufnr, view)
    sticky_header.redraw()
    view:render()
    vim.api.nvim_exec_autocmds("User", { pattern = "CsvViewAttach", data = bufnr })
  end)
end

--- disable csv table view
---@param bufnr integer?
function M.disable(bufnr)
  bufnr = buf.resolve_bufnr(bufnr)
  if not M.is_enabled(bufnr) then
    vim.notify("csvview: not enabled for this buffer.")
    return
  end

  views.detach(bufnr)
end

--- toggle csv table view
---@param bufnr integer?
---@param opts CsvView.Options?
function M.toggle(bufnr, opts)
  bufnr = buf.resolve_bufnr(bufnr)
  if M.is_enabled(bufnr) then
    M.disable(bufnr)
  else
    M.enable(bufnr, opts)
  end
end

--- setup
---@param opts CsvView.Options?
function M.setup(opts)
  config.setup(opts)
  sticky_header.setup()

  local group = vim.api.nvim_create_augroup("csvview.view", {})
  vim.api.nvim_create_autocmd({
    "WinEnter",
    "WinScrolled",
    "WinResized",
    "VimResized",
  }, {
    callback = views.render,
    group = group,
  })
end

return M
