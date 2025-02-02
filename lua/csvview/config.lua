local M = {}

---@class CsvView.Options.Parser
---@field async_chunksize? integer
---@field delimiter? CsvView.Options.Parser.Delimiter
---@field quote_char? string
---@field comments? string[]
---@alias CsvView.Options.Parser.Delimiter string | {default: string, ft: table<string,string>} | fun(bufnr:integer): string

---@class CsvView.Options.View
---@field min_column_width? integer
---@field spacing? integer
---@field display_mode? CsvView.Options.View.DisplayMode
---@alias CsvView.Options.View.DisplayMode "highlight" | "border"

---@class CsvView.Options.Keymaps
---@field textobject_field_inner? CsvView.Keymap
---@field textobject_field_outer? CsvView.Keymap
---@field jump_next_field_start? CsvView.Keymap
---@field jump_prev_field_start? CsvView.Keymap
---@field jump_next_field_end? CsvView.Keymap
---@field jump_prev_field_end? CsvView.Keymap
---@field jump_next_row? CsvView.Keymap
---@field jump_prev_row? CsvView.Keymap
---@field [string] CsvView.Keymap
---@field [number] CsvView.Keymap

---@alias CsvView.Options.Actions table<string, CsvView.Action>

--- @class CsvView.Options
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
    --- @type CsvView.Options.Parser.Delimiter
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
    quote_char = '"',

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
    ---@type CsvView.Options.View.DisplayMode
    display_mode = "highlight",
  },

  --- Keymaps for csvview.
  --- These mappings are only active when csvview is enabled.
  --- You can assign key mappings to each action defined in `opts.actions`.
  --- For example:
  --- ```lua
  --- keymaps = {
  ---   -- Text objects for selecting fields
  ---   textobject_field_inner = { "if", mode = { "o", "x" } },
  ---   textobject_field_outer = { "af", mode = { "o", "x" } },
  ---
  ---   -- Excel-like navigation:
  ---   -- Use <Tab> and <S-Tab> to move horizontally between fields.
  ---   -- Use <Enter> and <S-Enter> to move vertically between rows.
  ---   -- Note: In terminals, you may need to enable CSI-u mode to use <S-Tab> and <S-Enter>.
  ---   jump_next_field_end = { "<Tab>", mode = { "n", "v" } },
  ---   jump_prev_field_end = { "<S-Tab>", mode = { "n", "v" } },
  ---   jump_next_row = { "<Enter>", mode = { "n", "v" } },
  ---   jump_prev_row = { "<S-Enter>", mode = { "n", "v" } },
  ---
  ---   -- Custom key mapping example:
  ---   { "<leader>h", function() print("hello") end, mode = "n" },
  --- }
  --- ```
  --- @type CsvView.Options.Keymaps
  keymaps = {},

  --- Actions for keymaps.
  ---@type CsvView.Options.Actions
  actions = {
    textobject_field_inner = {
      function()
        require("csvview.textobject").field(0, { include_delimiter = false })
      end,
      desc = "[csvview] Select the current field",
      noremap = true,
      silent = true,
    },
    textobject_field_outer = {
      function()
        require("csvview.textobject").field(0, { include_delimiter = true })
      end,
      desc = "[csvview] Select the current field with delimiter",
      noremap = true,
      silent = true,
    },
    jump_next_field_start = {
      function()
        require("csvview.jump").next_field_start()
      end,
      desc = "[csvview] Jump to the next start of the field",
      noremap = true,
      silent = true,
    },
    jump_prev_field_start = {
      function()
        require("csvview.jump").prev_field_start()
      end,
      desc = "[csvview] Jump to the previous start of the field",
      noremap = true,
      silent = true,
    },
    jump_next_field_end = {
      function()
        require("csvview.jump").next_field_end()
      end,
      desc = "[csvview] Jump to the next end of the field",
      noremap = true,
      silent = true,
    },
    jump_prev_field_end = {
      function()
        require("csvview.jump").prev_field_end()
      end,
      desc = "[csvview] Jump to the previous end of the field",
      noremap = true,
      silent = true,
    },
    jump_next_row = {
      function()
        require("csvview.jump").field(0, { pos = { 1, 0 }, anchor = "end" })
      end,
      desc = "[csvview] Jump to the next row",
      noremap = true,
      silent = true,
    },
    jump_prev_row = {
      function()
        require("csvview.jump").field(0, { pos = { -1, 0 }, anchor = "end" })
      end,
      desc = "[csvview] Jump to the previous row",
      noremap = true,
      silent = true,
    },
  },
}

M.options = {}

--- get config
---@param opts? CsvView.Options
---@return CsvView.Options
function M.get(opts)
  return vim.tbl_deep_extend("force", M.options, opts or {})
end

--- setup
---@param opts? CsvView.Options
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
