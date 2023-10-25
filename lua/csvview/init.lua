local M = {}
local metrics = require("csvview.metrics")
local view = require("csvview.view")

--- @type integer[]
local enable_buffers = {}

--- register buffer events
---@param bufnr integer
---@param events { on_lines:function,on_reload:function}
local function register_events(bufnr, events)
  ---  on :e
  vim.b.csvview_update_auid = vim.api.nvim_create_autocmd({ "BufReadPost" }, {
    callback = function()
      register_events(bufnr, events)
      events.on_reload()
    end,
    buffer = bufnr,
    group = vim.api.nvim_create_augroup("CsvView", {}),
  })

  vim.api.nvim_buf_attach(bufnr, false, {
    on_lines = function(...)
      if not vim.tbl_contains(enable_buffers, bufnr) then
        return true
      end
      events.on_lines(...)
    end,
    on_reload = function()
      if not vim.tbl_contains(enable_buffers, bufnr) then
        return true
      end
      events.on_reload()
    end,
  })
end

--- unregister buffer events
---@param bufnr integer
local function unregister_events(bufnr)
  vim.api.nvim_del_autocmd(vim.b[bufnr].csvview_update_auid)
  vim.b[bufnr].csvview_update_auid = nil
end

--- enable csv table view
function M.enable()
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.tbl_contains(enable_buffers, bufnr) then
    print("csvview is already enabled.")
    return
  end
  table.insert(enable_buffers, bufnr)

  local item
  metrics.compute_csv_metrics(bufnr, function(csv)
    item = csv
    view.attach(bufnr, item)
  end)
  register_events(bufnr, {
    on_lines = function(_, _, _, first, last)
      item = metrics.compute_csv_metrics(bufnr, function(csv)
        item = csv
        view.update(bufnr, item)
      end, first + 1, last + 1, item.fields)
    end,
    on_reload = function()
      item = metrics.compute_csv_metrics(bufnr, function(csv)
        item = csv
        view.update(bufnr, item)
      end)
    end,
  })
end

--- disable csv table view
function M.disable()
  local bufnr = vim.api.nvim_get_current_buf()
  if not vim.tbl_contains(enable_buffers, bufnr) then
    print("csvview is not enabled for this buffer.")
    return
  end

  for i = #enable_buffers, 1, -1 do
    if enable_buffers[i] == bufnr then
      table.remove(enable_buffers, i)
    end
  end

  unregister_events(bufnr)
  view.detach(bufnr)
end

--- setup
function M.setup()
  vim.api.nvim_create_user_command("CsvViewEnable", M.enable, {})
  vim.api.nvim_create_user_command("CsvViewDisable", M.disable, {})
  view.setup()
end

return M
