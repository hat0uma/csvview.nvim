local M = {}

local CsvViewMetrics = require("csvview.metrics")
local buffer_event = require("csvview.buffer_event")
local config = require("csvview.config")
local view = require("csvview.view")

--- check if csv table view is enabled
---@param bufnr integer
---@return boolean
function M.is_enabled(bufnr)
  return view.get(bufnr) ~= nil
end

--- enable csv table view
---@param bufnr integer?
---@param opts CsvView.Options?
function M.enable(bufnr, opts)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  opts = config.get(opts)

  if M.is_enabled(bufnr) then
    vim.notify("csvview: already enabled for this buffer.")
    return
  end

  -- Calculate metrics and attach view.
  local metrics = CsvViewMetrics:new(bufnr, opts)
  metrics:compute_buffer(function()
    view.attach(bufnr, metrics, opts)
  end)

  -- Register buffer events.
  buffer_event.register(bufnr, {
    on_lines = function(_, _, _, first, last, last_updated)
      -- detach if disabled
      if not M.is_enabled(bufnr) then
        return true
      end

      -- Recalculate only the difference.
      metrics:update(first, last, last_updated)
    end,

    on_reload = function()
      -- detach if disabled
      if not M.is_enabled(bufnr) then
        return true
      end

      -- Recalculate all fields.
      view.detach(bufnr)
      metrics:compute_buffer(function()
        view.attach(bufnr, metrics, opts)
      end)
    end,
  })
end

--- disable csv table view
---@param bufnr integer?
function M.disable(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not M.is_enabled(bufnr) then
    vim.notify("csvview: not enabled for this buffer.")
    return
  end

  -- Unregister buffer events and detach view.
  buffer_event.unregister(bufnr)
  view.detach(bufnr)
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
  view.setup()
end

return M
