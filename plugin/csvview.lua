local Cmdline = require("csvview.cmdline")
local csvview = require("csvview")

local cmdline = Cmdline:new({
  {
    name = "delimiter",
    ---@param options CsvView.Options
    ---@param value string
    set = function(options, value)
      options.parser.delimiter = value
    end,
  },
  {
    name = "quote_char",
    ---@param options CsvView.Options
    ---@param value string
    set = function(options, value)
      options.parser.quote_char = value
    end,
  },
  {
    name = "comment",
    ---@param options CsvView.Options
    ---@param value string
    set = function(options, value)
      options.parser.comments = { value }
    end,
  },
  {
    name = "display_mode",
    ---@param options CsvView.Options
    ---@param value string
    set = function(options, value)
      options.view.display_mode = value
    end,
    candidates = { "highlight", "border" },
  },
  {
    name = "header_lnum",
    ---@param options CsvView.Options
    ---@param value string
    set = function(options, value)
      if value == "false" then
        options.view.header_lnum = false
      else
        options.view.header_lnum = tonumber(value)
      end
    end,
  },
})

local function create_empty_opts()
  return {
    parser = {},
    view = {},
  }
end

vim.api.nvim_create_user_command("CsvViewEnable", function(opts)
  local bufnr = vim.api.nvim_get_current_buf()
  local cmdopts = cmdline:parse(opts.args, create_empty_opts())
  csvview.enable(bufnr, cmdopts)
end, {
  desc = "[csvview] Enable csvview",
  nargs = "?",
  complete = function(arg_lead, cmd_line, cursor_pos)
    return cmdline:complete(arg_lead, cmd_line, cursor_pos)
  end,
})

vim.api.nvim_create_user_command("CsvViewDisable", function()
  csvview.disable()
end, {
  desc = "[csvview] Disable csvview",
})

vim.api.nvim_create_user_command("CsvViewToggle", function(opts)
  local bufnr = vim.api.nvim_get_current_buf()
  local cmdopts = cmdline:parse(opts.args, create_empty_opts())
  csvview.toggle(bufnr, cmdopts)
end, {
  desc = "[csvview] Toggle csvview",
  nargs = "?",
  complete = function(arg_lead, cmd_line, cursor_pos)
    return cmdline:complete(arg_lead, cmd_line, cursor_pos)
  end,
})
