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
---@field header_lnum? integer|false
---@field sticky_header? CsvView.Options.View.StickyHeader
---@alias CsvView.Options.View.DisplayMode "highlight" | "border"

---@class CsvView.Options.View.StickyHeader
---@field enabled? boolean
---@field separator? string|false

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
--- @field parser? CsvView.Options.Parser
--- @field view? CsvView.Options.View
--- @field keymaps? CsvView.Options.Keymaps
--- @field actions? table<string, CsvView.Action>

--- @class CsvView.InternalOptions
M.defaults = {
  parser = {
    --- The number of lines that the asynchronous parser processes per cycle.
    --- This setting is used to prevent monopolization of the main thread when displaying large files.
    --- If the UI freezes, try reducing this value.
    --- @type integer
    async_chunksize = 50,

    --- The delimiter character
    --- You can specify a string, a table of delimiter characters for each file type, or a function that returns a delimiter character.
    --- Currently, only fixed-length strings are supported. Regular expressions such as \s+ are not supported.
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
    --- You can also specify it on the command line.
    --- e.g:
    --- :CsvViewEnable display_mode=border
    ---@type CsvView.Options.View.DisplayMode
    display_mode = "highlight",

    --- The line number of the header
    --- If this is set, the line is treated as a header. and used for sticky header feature.
    --- see also: `view.sticky_header`
    --- @type integer|false
    header_lnum = false,

    --- The sticky header feature settings
    --- If `view.header_lnum` is set, the header line is displayed at the top of the window.
    sticky_header = {
      --- Whether to enable the sticky header feature
      --- @type boolean
      enabled = true,

      --- The separator character for the sticky header window
      --- set `false` to disable the separator
      --- @type string|false
      separator = "─",
    },
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
        for _ = 1, vim.v.count1 do
          require("csvview.jump").next_field_start()
        end
      end,
      desc = "[csvview] Jump to the next start of the field",
      noremap = true,
      silent = true,
    },
    jump_prev_field_start = {
      function()
        for _ = 1, vim.v.count1 do
          require("csvview.jump").prev_field_start()
        end
      end,
      desc = "[csvview] Jump to the previous start of the field",
      noremap = true,
      silent = true,
    },
    jump_next_field_end = {
      function()
        for _ = 1, vim.v.count1 do
          require("csvview.jump").next_field_end()
        end
      end,
      desc = "[csvview] Jump to the next end of the field",
      noremap = true,
      silent = true,
    },
    jump_prev_field_end = {
      function()
        for _ = 1, vim.v.count1 do
          require("csvview.jump").prev_field_end()
        end
      end,
      desc = "[csvview] Jump to the previous end of the field",
      noremap = true,
      silent = true,
    },
    jump_next_row = {
      function()
        require("csvview.jump").field(0, { pos = { vim.v.count1, 0 }, anchor = "end" })
      end,
      desc = "[csvview] Jump to the next row",
      noremap = true,
      silent = true,
    },
    jump_prev_row = {
      function()
        require("csvview.jump").field(0, { pos = { -vim.v.count1, 0 }, anchor = "end" })
      end,
      desc = "[csvview] Jump to the previous row",
      noremap = true,
      silent = true,
    },
  },
}

---@diagnostic disable-next-line: missing-fields
M.options = {}

---@type { name: string, link?: string }[]
M._highlights = {
  { name = "CsvViewDelimiter", link = "Delimiter" },
  { name = "CsvViewComment", link = "Comment" },
  { name = "CsvViewHeaderLine", link = nil },
  { name = "CsvViewStickyHeaderSeparator", link = "Delimiter" },
  -- use built-in csv syntax highlight group.
  { name = "CsvViewCol0", link = "csvCol0" },
  { name = "CsvViewCol1", link = "csvCol1" },
  { name = "CsvViewCol2", link = "csvCol2" },
  { name = "CsvViewCol3", link = "csvCol3" },
  { name = "CsvViewCol4", link = "csvCol4" },
  { name = "CsvViewCol5", link = "csvCol5" },
  { name = "CsvViewCol6", link = "csvCol6" },
  { name = "CsvViewCol7", link = "csvCol7" },
  { name = "CsvViewCol8", link = "csvCol8" },
}

--- get config
---@param opts? CsvView.Options
---@return CsvView.InternalOptions
function M.get(opts)
  return vim.tbl_deep_extend("force", M.options, opts or {})
end

--- setup
---@param opts? CsvView.Options
function M.setup(opts)
  -- Set colors
  for _, hl in ipairs(M._highlights) do
    vim.api.nvim_set_hl(0, hl.name, { link = hl.link, default = true })
  end

  if vim.fn.has("nvim-0.11") ~= 1 then
    -- fallback for nvim < 0.11
    -- see https://github.com/neovim/neovim/blob/master/runtime/syntax/csv.vim
    local fallback_highlights = {
      csvCol1 = "Statement",
      csvCol2 = "Constant",
      csvCol3 = "Type",
      csvCol4 = "PreProc",
      csvCol5 = "Identifier",
      csvCol6 = "Special",
      csvCol7 = "String",
      csvCol8 = "Comment",
    }
    for name, link in pairs(fallback_highlights) do
      if vim.tbl_isempty(vim.api.nvim_get_hl(0, { name = name })) then
        vim.api.nvim_set_hl(0, name, { link = link, default = true })
      end
    end
  end

  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

--- Resolve delimiter character
---@param opts CsvView.InternalOptions
---@param bufnr integer
---@return string
function M.resolve_delimiter(opts, bufnr)
  local delim = opts.parser.delimiter
  ---@diagnostic disable-next-line: no-unknown
  local char
  if type(delim) == "function" then
    char = delim(bufnr)
  end

  if type(delim) == "table" then
    char = delim.ft[vim.bo.filetype] or delim.default
  end

  if type(delim) == "string" then
    char = delim
  end

  assert(type(char) == "string", string.format("unknown delimiter type: %s", type(char)))
  return char
end

return M
