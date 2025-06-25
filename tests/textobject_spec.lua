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
    table.concat({ "abc" }, delimiter),
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
    {
      name = "select the current field with delimiter. The cursor is first and last column",
      cursor = { row = 5, col = 0 },
      opts = { include_delimiter = true },
      expected = "abc",
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

  describe("multi-line fields", function()
    local testutil = require("tests.testutil")

    ---@type CsvView.Options
    local opts = {
      parser = {
        comments = { "#" },
        delimiter = ",",
      },
    }

    ---@type CsvView.TextObjectCase[]
    local multiline_cases = {
      {
        name = "selects multi-line field without delimiter",
        cursor = { row = 4, col = 5 }, -- in address field
        opts = { include_delimiter = false },
        expected = '"123 Main St\nApt 4B\nNew York, NY 10001"',
      },
      {
        name = "selects multi-line field with delimiter The cursor is not last column",
        cursor = { row = 3, col = 20 }, -- in address field
        opts = { include_delimiter = true },
        expected = '"123 Main St\nApt 4B\nNew York, NY 10001",',
      },
      {
        name = "selects multi-line field with delimiter. The cursor is last column",
        cursor = { row = 6, col = 5 }, -- in note field
        opts = { include_delimiter = true },
        expected = ',"Customer since 2020\nPrefers email contact\nHas special delivery instructions:\n- Ring doorbell twice\n- Leave package at door"',
      },
    }

    --- Run multi-line field test cases
    ---@param cases CsvView.TextObjectCase[]
    local function run_multiline_tests(cases)
      for _, case in ipairs(cases) do
        it(case.name, function()
          local lines = testutil.readlines("tests/fixtures/multiline.csv")
          local bufnr = vim.api.nvim_create_buf(false, true)
          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
          vim.api.nvim_win_set_buf(0, bufnr)

          local co = coroutine.running()
          csvview.enable(bufnr, opts)
          testutil.yield_next_loop(co)

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

    run_multiline_tests(multiline_cases)
  end)
end)
