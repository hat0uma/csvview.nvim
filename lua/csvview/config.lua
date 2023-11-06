local M = {}

--- @class CsvViewOptions
M.defaults = {
  parser = {
    --- The number of lines that the asynchronous parser processes per cycle.
    --- This setting is used to prevent monopolization of the main thread when displaying large files.
    --- If the UI freezes, try reducing this value.
    async_chunksize = 50,
  },
  view = {
    --- minimum width of a column
    min_column_width = 5,
    --- spacing between columns
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
