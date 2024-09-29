local csvview = require("csvview")

--- unescape delimiter
---@param delimiter string | nil
---@return string | nil
local function unescape(delimiter)
  if delimiter == nil or delimiter == "" then
    return nil
  end

  return (
    delimiter
      :gsub("\\t", "\t") -- tab
      :gsub("\\ ", " ") -- space
      :sub(1, 1) -- only first character
  )
end

--- Get options for csvview
---@param args string
---@return CsvViewOptions
local function opts_for_command(args)
  local delimiter = unescape(args)
  return {
    parser = {
      delimiter = delimiter,
    },
  }
end

vim.api.nvim_create_user_command("CsvViewEnable", function(opts)
  -- args: delimiter (optional)
  local bufnr = vim.api.nvim_get_current_buf()
  csvview.enable(bufnr, opts_for_command(opts.args))
end, {
  desc = "[csvview] Enable csvview",
  nargs = "?",
})

vim.api.nvim_create_user_command("CsvViewDisable", function()
  csvview.disable()
end, {
  desc = "[csvview] Disable csvview",
})

vim.api.nvim_create_user_command("CsvViewToggle", function(opts)
  -- args: delimiter (optional)
  local bufnr = vim.api.nvim_get_current_buf()
  csvview.toggle(bufnr, opts_for_command(opts.args))
end, {
  desc = "[csvview] Toggle csvview",
  nargs = "?",
})
