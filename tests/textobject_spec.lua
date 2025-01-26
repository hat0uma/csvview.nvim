---@diagnostic disable: await-in-sync
local config = require("csvview.config")
local csvview = require("csvview")
local textobject = require("csvview.textobject")

---@type CsvView.Options
local opts = { parser = { comments = { "#" } } }

local lines = {
  "Index,ID,Name,Email,Birthday",
  "1,XUMMW7737A,Jane Davis,jane.williams@example.org,1964-03-22",
  "# this is a comment",
  "",
}

---@class CsvView.TextObjectCase
---@field name string
---@field cursor { row: integer, col: integer } 1-based row and 0-based column
---@field opts { include_delimiter: boolean }
---@field expected string

---@type CsvView.TextObjectCase[]
local cases = {
  {
    name = "selects the current field without delimiter",
    cursor = { row = 2, col = string.find(lines[2], "M") }, ---@diagnostic disable-line
    opts = { include_delimiter = false },
    expected = "XUMMW7737A",
  },
  {
    name = "selects the current field with delimiter. The cursor is first column",
    cursor = { row = 2, col = 0 },
    opts = { include_delimiter = true },
    expected = "1,",
  },
  {
    name = "selects the current field with delimiter. The cursor is last column",
    cursor = { row = 2, col = string.find(lines[2], "4") }, ---@diagnostic disable-line
    opts = { include_delimiter = true },
    expected = ",1964-03-22",
  },
  {
    name = "select nothing if the cursor is on a comment line",
    cursor = { row = 3, col = 0 },
    opts = { include_delimiter = false },
    expected = "",
  },
  {
    name = "select nothing if the cursor is on an empty line",
    cursor = { row = 4, col = 0 },
    opts = { include_delimiter = false },
    expected = "",
  },
}

describe("csvview.textobject", function()
  before_each(function()
    config.setup()
    csvview.setup()
  end)

  for _, case in ipairs(cases) do
    it(case.name, function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      vim.api.nvim_win_set_buf(0, bufnr)

      csvview.enable(bufnr, opts)

      -- Move cursor to the specified field
      vim.api.nvim_win_set_cursor(0, { case.cursor.row, case.cursor.col })
      textobject.field(bufnr, case.opts)

      -- Clear the register
      vim.fn.setreg("0", "")

      -- Copy the selected text
      vim.cmd("normal! y")
      local selected = vim.fn.getreg("0")
      assert.are.same(case.expected, selected)
    end)
  end
end)
