local M = {}

local CsvView = require("csvview.view").View
local get_view = require("csvview.view").get
local attach_view = require("csvview.view").attach
local detach_view = require("csvview.view").detach
local setup_view = require("csvview.view").setup

local CsvViewMetrics = require("csvview.metrics")
local buf = require("csvview.buf")
local config = require("csvview.config")
local keymap = require("csvview.keymap")

--- check if csv table view is enabled
---@param bufnr integer
---@return boolean
function M.is_enabled(bufnr)
  return get_view(bufnr) ~= nil
end

--- enable csv table view
---@param bufnr integer?
---@param opts CsvView.Options?
function M.enable(bufnr, opts)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
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
    on_lines = function(_, _, _, first, last, last_updated)
      metrics:update(first, last, last_updated)
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
  bufnr = bufnr or vim.api.nvim_get_current_buf()
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
  bufnr = bufnr or vim.api.nvim_get_current_buf()
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
end

return M
