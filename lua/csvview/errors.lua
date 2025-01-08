--- Error handling utilities
local M = {}

--- @class CsvView.Error
--- @field err string error message
--- @field stacktrace? string error stacktrace
--- @field [string] any additional context data

--- Wrap error with stacktrace for `xpcall`
---@param err string|CsvView.Error|nil
---@return CsvView.Error
function M.wrap_stacktrace(err)
  if type(err) == "table" then
    return vim.tbl_deep_extend("keep", err, { stacktrace = debug.traceback("", 2) })
  else
    return { err = err, stacktrace = debug.traceback("", 2) }
  end
end

--- Propagate error with context
---@param err string|CsvView.Error|nil
---@param context table<string,any>| nil
function M.error_with_context(err, context)
  if type(err) == "string" then
    err = vim.tbl_deep_extend("keep", { err = err }, context or {})
  elseif type(err) == "table" then
    err = vim.tbl_deep_extend("keep", err, context or {})
  end
  error(err, 0)
end

--- Remove key from table
---@param tbl table
---@param key string
---@return any
local function tbl_remove_key(tbl, key)
  local value = tbl[key] ---@type any
  tbl[key] = nil ---@type any
  return value
end

--- Print error message
--- @type fun(header: string, err: string|CsvView.Error|nil)
M.print_structured_error = vim.schedule_wrap(function(header, err)
  --- @type string
  local msg

  if type(err) == "table" then
    -- extract error message and stacktrace
    local stacktrace = tbl_remove_key(err, "stacktrace") or "No stacktrace available"
    local err_msg = tbl_remove_key(err, "err") or "An unspecified error occurred"

    -- format error message
    msg = string.format(
      "Error: %s\nDetails: %s\n%s",
      err_msg,
      -- vim.inspect(err, { newline = " ", indent = "" }),
      vim.inspect(err),
      stacktrace --
    )
  elseif type(err) == "string" then
    msg = err
  else
    msg = "An unknown error occurred."
  end

  vim.notify(string.format("%s\n\n%s", header, msg), vim.log.levels.ERROR, { title = "csvview.nvim" })
end)

return M
