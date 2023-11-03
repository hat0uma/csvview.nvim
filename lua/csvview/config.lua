local M = {}

--- @class CsvViewOptions
M.defaults = {
  parser = {
    async_chunksize = 50,
  },
  view = {
    min_column_width = 5,
    spacing = 2,
  },
}

M.options = {}

--- get config
---@param opts? CsvViewOptions
---@return CsvViewOptions
function M.get(opts)
  return vim.tbl_deep_extend("force", M.options, opts or {})
end

--- setup
---@param opts? CsvViewOptions
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
