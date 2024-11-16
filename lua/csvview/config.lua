local M = {}

--- @class CsvViewOptions
M.defaults = {
  parser = {
    --- The number of lines that the asynchronous parser processes per cycle.
    --- This setting is used to prevent monopolization of the main thread when displaying large files.
    --- If the UI freezes, try reducing this value.
    --- @type integer
    async_chunksize = 50,

    --- The delimiter character
    --- You can specify a string, a table of delimiter characters for each file type, or a function that returns a delimiter character.
    --- e.g:
    ---  delimiter = ","
    ---  delimiter = function(bufnr) return "," end
    ---  delimiter = {
    ---    default = ",",
    ---    ft = {
    ---      tsv = "\t",
    ---    },
    ---  }
    --- @type string | {default: string, ft: table<string,string>} | fun(bufnr:integer): string
    delimiter = {
      default = ",",
      ft = {
        tsv = "\t",
      },
    },

    --- The quote character
    --- If a field is enclosed in this character, it is treated as a single field and the delimiter in it will be ignored.
    --- e.g:
    ---  quote_char= "'"
    --- You can also specify it on the command line.
    --- e.g:
    --- :CsvViewEnable quote_char='
    --- @type string
    quote_char = "\"",

    --- The comment prefix characters
    --- If the line starts with one of these characters, it is treated as a comment.
    --- Comment lines are not displayed in tabular format.
    --- You can also specify it on the command line.
    --- e.g:
    --- :CsvViewEnable comment=#
    --- @type string[]
    comments = {
      -- "#",
      -- "--",
      -- "//",
    },
  },
  view = {
    --- minimum width of a column
    --- @type integer
    min_column_width = 5,

    --- spacing between columns
    --- @type integer
    spacing = 2,

    --- The display method of the delimiter
    --- "highlight" highlights the delimiter
    --- "border" displays the delimiter with `│`
    ---@type "highlight" | "border"
    display_mode = "highlight",
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
