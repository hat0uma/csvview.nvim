local csvview = require("csvview")

local opts_keys = {
  "delimiter",
  "quote_char",
  "comment",
}

--- unescape delimiter
---@param value string
---@return string
local function unescape(value)
  return (
    value
      :gsub("\\t", "\t") -- tab
      :gsub("\\ ", " ") -- space
  )
end

--- Parse options from command line
---@param args string
---@return {key: string, value: string}[]
local function parse_cmdline_opts(args)
  local P = vim.lpeg.P
  local Cg = vim.lpeg.Cg
  local Ct = vim.lpeg.Ct
  local space = P(" ")
  local escaped_space = P("\\ ")
  local kv_sep = P("=")

  -- define key=value pair
  local key = Cg((1 - (space + kv_sep)) ^ 1, "key")
  local value = Cg((escaped_space + (1 - space)) ^ 1, "value")
  local pair = Ct(key * kv_sep * value)
  local pattern = Ct(pair * (space * pair) ^ 0)

  --- @type {key: string, value: string}[]
  local options = pattern:match(args) or {}
  return vim.tbl_map(
    ---@param matched {key: string, value: string}
    ---@return {key: string, value: string}
    function(matched)
      return {
        key = matched.key,
        value = unescape(matched.value),
      }
    end,
    options
  )
end

--- Get options for csvview
---@param args string
---@return CsvViewOptions
local function opts_for_command(args)
  ---@type CsvViewOptions
  local opts = { parser = {}, view = {} }
  local cmdline_opts = parse_cmdline_opts(args)
  for _, opt in ipairs(cmdline_opts) do
    if opt.key == "delimiter" then
      opts.parser.delimiter = opt.value
    elseif opt.key == "quote_char" then
      opts.parser.quote_char = opt.value
    elseif opt.key == "comment" then
      opts.parser.comments = { opt.value }
    end
  end
  return opts
end

--- Complete options for CsvView commands
---@param arg_lead string
---@param cmd_line string
---@param cursor_pos integer
---@return string[]
local function opts_complete(arg_lead, cmd_line, cursor_pos)
  -- print(arg_lead, cmd_line, cursor_pos)
  local opts_candidates = vim.tbl_map(
    ---@param v string
    ---@return string
    function(v)
      return v .. "="
    end,
    opts_keys
  )

  --- Check if the command line already has the key
  ---@param key string
  ---@return boolean
  local function already_has_opts(key)
    return string.find(cmd_line, key, 1, true) ~= nil and not vim.endswith(cmd_line, key)
  end

  return vim.tbl_filter(
    ---@param v string
    ---@return string
    function(v)
      return vim.startswith(v, arg_lead) and not already_has_opts(v)
    end,
    opts_candidates
  )
end

vim.api.nvim_create_user_command("CsvViewEnable", function(opts)
  local bufnr = vim.api.nvim_get_current_buf()
  local cmdopts = opts_for_command(opts.args)
  csvview.enable(bufnr, cmdopts)
end, {
  desc = "[csvview] Enable csvview",
  nargs = "?",
  complete = opts_complete,
})

vim.api.nvim_create_user_command("CsvViewDisable", function()
  csvview.disable()
end, {
  desc = "[csvview] Disable csvview",
})

vim.api.nvim_create_user_command("CsvViewToggle", function(opts)
  local bufnr = vim.api.nvim_get_current_buf()
  local cmdopts = opts_for_command(opts.args)
  csvview.toggle(bufnr, cmdopts)
end, {
  desc = "[csvview] Toggle csvview",
  nargs = "?",
  complete = opts_complete,
})
