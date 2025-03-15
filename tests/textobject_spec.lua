---@diagnostic disable: await-in-sync
local config = require("csvview.config")
local csvview = require("csvview")
local textobject = require("csvview.textobject")

local function create_test(delimiter)
  ---@type CsvView.Options
  local opts = {
    parser = {
      comments = { "#" },
      delimiter = delimiter,
    },
  }

  ---@type string[]
  local lines = {
    table.concat({ "Index", "ID", "Name", "Email", "Birthday" }, delimiter),
    table.concat({ "1", "XUMMW7737A", "Jane Davis", "jane.williams@example.org", "1964-03-22" }, delimiter),
    table.concat({ "# this is a comment" }, delimiter),
    table.concat({ "" }, delimiter),
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
      expected = "1" .. delimiter,
    },
    {
      name = "selects the current field with delimiter. The cursor is last column",
      cursor = { row = 2, col = string.find(lines[2], "4") }, ---@diagnostic disable-line
      opts = { include_delimiter = true },
      expected = delimiter .. "1964-03-22",
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
  return opts, lines, cases
end

describe("textobject", function()
  before_each(function()
    config.setup()
    csvview.setup()
  end)

  --- Run the test cases
  ---@param opts CsvView.Options
  ---@param lines string[]
  ---@param cases CsvView.TextObjectCase[]
  local function run(opts, lines, cases)
    for _, case in ipairs(cases) do
      it(string.format("(delimiter=%s) field %s", opts.parser.delimiter, case.name), function()
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
  end

  run(create_test(","))
  run(create_test("|||"))
end)
