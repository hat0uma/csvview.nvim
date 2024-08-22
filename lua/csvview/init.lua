local M = {}
local config = require("csvview.config")
local metrics = require("csvview.metrics")
local view = require("csvview.view")

--- @type integer[]
local enable_buffers = {}

--- register buffer events
---@param bufnr integer
---@param events { on_lines:function,on_reload:function}
local function register_events(bufnr, events)
  ---  on :e
  vim.b[bufnr].csvview_update_auid = vim.api.nvim_create_autocmd({ "BufReadPost" }, {
    callback = function()
      register_events(bufnr, events)
      events.on_reload()
    end,
    buffer = bufnr,
    once = true,
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
---@param bufnr integer?
---@param opts CsvViewOptions?
function M.enable(bufnr, opts)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if vim.tbl_contains(enable_buffers, bufnr) then
    vim.notify("csvview: already enabled for this buffer.")
    return
  end
  table.insert(enable_buffers, bufnr)

  local fields = {}
  opts = config.get(opts)
  metrics.compute_csv_metrics(bufnr, opts, function(f, column_max_widths)
    fields = f
    view.attach(bufnr, fields, column_max_widths, opts)
  end)
  register_events(bufnr, {
    ---@type fun(_,_,_,first:integer,last:integer,last_updated:integer)
    on_lines = function(_, _, _, first, last, last_updated)
      if last > last_updated then
        -- when line deleted.
        for _ = last_updated + 1, last do
          table.remove(fields, last_updated + 1)
        end
      elseif last < last_updated then
        -- when line added.
        for i = last + 1, last_updated do
          table.insert(fields, i, {})
        end
      else
        -- when updated within a line.
      end

      local startlnum = first + 1
      local endlnum = last_updated
      metrics.compute_csv_metrics(bufnr, opts, function(f, column_max_widths)
        fields = f
        view.update(bufnr, fields, column_max_widths)
      end, startlnum, endlnum, fields)
    end,

    on_reload = function()
      view.detach(bufnr)
      metrics.compute_csv_metrics(bufnr, opts, function(f, column_max_widths)
        fields = f
        view.attach(bufnr, fields, column_max_widths, opts)
      end)
    end,
  })
end

--- disable csv table view
function M.disable()
  local bufnr = vim.api.nvim_get_current_buf()
  if not vim.tbl_contains(enable_buffers, bufnr) then
    vim.notify("csvview: not enabled for this buffer.")
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
---@param opts CsvViewOptions?
function M.setup(opts)
  config.setup(opts)
  view.setup()
  vim.api.nvim_create_user_command("CsvViewEnable", function()
    M.enable()
  end, {})
  vim.api.nvim_create_user_command("CsvViewDisable", function()
    M.disable()
  end, {})
end

return M
