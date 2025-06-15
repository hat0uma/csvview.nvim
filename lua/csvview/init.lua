local M = {}

local CsvView = require("csvview.view").View
local errors = require("csvview.errors")
local sticky_header = require("csvview.sticky_header")
local views = require("csvview.view")

local CsvViewMetrics = require("csvview.metrics")
local CsvViewParser = require("csvview.parser")
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
  local parser = CsvViewParser:new(bufnr, opts)
  local metrics = CsvViewMetrics:new(bufnr, opts, parser)
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
            view:clear()
          end,
          once = true,
        })
      else
        -- Handle normal buffer update events
        view:lock()
        metrics:update(first, last, last_updated, function(err)
          if err and err ~= "cancelled" then
            vim.notify("csvview: failed to update metrics: " .. err, vim.log.levels.ERROR)
            M.disable(bufnr)
            return
          end

          view:unlock()
          view:clear()
        end)
      end
    end,
    on_reload = function()
      -- Clear and recompute metrics when buffer is reloaded
      view:clear()
      metrics:clear()
      view:lock()
      metrics:compute_buffer(function(err)
        if err then
          vim.notify("csvview: failed to compute metrics: " .. err, vim.log.levels.ERROR)
          M.disable(bufnr)
          return
        end

        view:unlock()
      end)
    end,
  })

  local orig_syntax = vim.bo[bufnr].syntax

  -- Register detach callback
  on_detach = function()
    detach_bufevent_handle()
    metrics:clear()
    keymap.unregister(opts)
    sticky_header.redraw()
    vim.bo[bufnr].syntax = orig_syntax
    vim.api.nvim_exec_autocmds("User", { pattern = "CsvViewDetach", data = bufnr })
  end

  -- Calculate metrics and attach view.
  metrics:compute_buffer(function(err)
    if err then
      vim.notify("csvview: failed to compute metrics: " .. err, vim.log.levels.ERROR)
      return
    end

    -- disable builtin syntax highlighting.
    -- NOTE: This is necessary to prevent syntax highlighting from interfering with the custom highlighting of the view.
    vim.bo[bufnr].syntax = ""

    keymap.register(opts)
    views.attach(bufnr, view)
    sticky_header.redraw()
    vim.cmd([[redraw!]])
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

--- Register autocmds
---@param autocmds { event: string|string[], pattern?: string|string[], callback: fun(args: vim.api.keyset.create_autocmd.callback_args) }[]
---@param group string|integer
local function register_autocmds(autocmds, group)
  for _, au in ipairs(autocmds) do
    vim.api.nvim_create_autocmd(au.event, { group = group, pattern = au.pattern, callback = au.callback })
  end
end

--- setup
---@param opts CsvView.Options?
function M.setup(opts)
  -- Set default options
  config.setup(opts)

  -- Register view rendering trigger
  local ns = vim.api.nvim_create_namespace("csvview.view")
  vim.api.nvim_set_decoration_provider(ns, {
    on_win = function(_, _, bufnr, toprow, botrow)
      local view = views.get(bufnr)
      if not view or view:is_locked() then
        return false
      end

      local ok, err = xpcall(view.render_lines, errors.wrap_stacktrace, view, toprow + 1, botrow + 1)
      if not ok then
        errors.print_structured_error("CsvView Rendering Stopped with Error", err)
        views.detach(view.bufnr)
      end
      return false
    end,
  })

  -- Register autocmds
  local group = vim.api.nvim_create_augroup("csvview", {})
  register_autocmds({
    { -- `CursorMoved` is necessary to hide the sticky header when cursor overlaps the header.
      event = { "WinEnter", "WinScrolled", "WinResized", "VimResized", "CursorMoved" },
      callback = sticky_header.redraw,
    },
    {
      event = "OptionSet",
      pattern = { "number", "relativenumber", "numberwidth", "signcolumn", "foldcolumn" },
      callback = sticky_header.redraw,
    },
    {
      event = "WinClosed",
      callback = function(args)
        local winid = assert(tonumber(args.match))
        sticky_header.close_if_opened(winid)
      end,
    },
    { -- Detach view when the buffer is deleted
      event = "BufUnload",
      callback = function(args)
        local bufnr = assert(tonumber(args.buf))
        local view = views.get(bufnr)
        if view then
          views.detach(bufnr)
        end
      end,
    },
  }, group)
end

return M
