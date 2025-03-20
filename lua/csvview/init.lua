local M = {}

local CsvView = require("csvview.view").View
local get_view = require("csvview.view").get
local attach_view = require("csvview.view").attach
local detach_view = require("csvview.view").detach
local setup_view = require("csvview.view").setup
local sticky_header = require("csvview.sticky_header")

local CsvViewMetrics = require("csvview.metrics")
local buf = require("csvview.buf")
local config = require("csvview.config")
local keymap = require("csvview.keymap")

--- check if csv table view is enabled
---@param bufnr integer
---@return boolean
function M.is_enabled(bufnr)
  bufnr = buf.resolve_bufnr(bufnr)
  return get_view(bufnr) ~= nil
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
        view:clear()
        view:lock()
        metrics:update(first, last, last_updated, function()
          view:unlock()
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

  -- Register detach callback
  on_detach = function()
    vim.api.nvim_clear_autocmds({ group = group, buffer = bufnr })
    detach_bufevent_handle()
    metrics:clear()
    keymap.unregister(opts)
    vim.api.nvim_exec_autocmds("User", { pattern = "CsvViewDetach" })
  end

  -- Calculate metrics and attach view.
  metrics:compute_buffer(function()
    attach_view(bufnr, view)
    keymap.register(opts)
    vim.api.nvim_exec_autocmds("User", { pattern = "CsvViewAttach" })
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

  detach_view(bufnr)
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
  setup_view()
  sticky_header.setup()
end

return M
