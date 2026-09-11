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

  describe("column", function()
    local testutil = require("tests.testutil")

    -- The column text object is built on the built-in multicursor feature.
    if not vim.api.nvim_mcursor then
      it("skipped: the column text object requires Neovim 0.13 or later", function() end)
      return
    end

    ---@type CsvView.Options
    local opts = {
      parser = { comments = { "#" }, delimiter = "," },
      view = { header_lnum = 1 },
    }

    ---@type string[]
    local lines = {
      "name,age,city",
      "alice,20,NY",
      "# comment",
      "",
      "bob,31,LA",
      "carol,42",
    }

    --- Open a buffer with csvview enabled and map the column text object to `ic`.
    ---@async
    ---@param buflines string[]
    ---@param textobject_opts { include_delimiter?: boolean, include_header?: boolean }
    ---@param csvview_opts CsvView.Options
    ---@return integer bufnr
    local function setup_buffer(buflines, textobject_opts, csvview_opts)
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, buflines)
      vim.api.nvim_win_set_buf(0, bufnr)

      local co = coroutine.running()
      csvview.enable(bufnr, csvview_opts)
      testutil.yield_next_loop(co)

      vim.keymap.set({ "o", "x" }, "ic", function()
        textobject.column(bufnr, textobject_opts)
      end, { buffer = bufnr })

      return bufnr
    end

    before_each(function()
      -- Multicursors are per-buffer, but make sure no session leaks into the next test.
      pcall(vim.api.nvim_buf_clear_namespace, 0, vim.api.nvim_create_namespace("nvim.multicursor"), 0, -1)
    end)

    it("places a cursor on each row of the column and edits them at once", function()
      local co = coroutine.running()
      local bufnr = setup_buffer(lines, { include_delimiter = false }, opts)

      vim.api.nvim_win_set_cursor(0, { 2, 6 }) -- "20" of the age column
      testutil.feedkeys(co, "cicX<Esc>")

      assert.are.same({
        "name,age,city", -- the header row is not edited by default
        "alice,X,NY",
        "# comment", -- comment lines have no field
        "", -- empty lines have no field
        "bob,X,LA",
        "carol,X",
      }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    end)

    it("skips rows that do not have the column", function()
      local co = coroutine.running()
      local bufnr = setup_buffer(lines, { include_delimiter = false }, opts)

      vim.api.nvim_win_set_cursor(0, { 2, 9 }) -- "NY" of the city column
      testutil.feedkeys(co, "cicX<Esc>")

      assert.are.same({
        "name,age,city",
        "alice,20,X",
        "# comment",
        "",
        "bob,31,X",
        "carol,42", -- this row has no third column
      }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    end)

    it("includes the header row when `include_header` is set", function()
      local co = coroutine.running()
      local bufnr = setup_buffer(lines, { include_delimiter = false, include_header = true }, opts)

      vim.api.nvim_win_set_cursor(0, { 2, 6 }) -- "20" of the age column
      testutil.feedkeys(co, "cicX<Esc>")

      assert.are.same({
        "name,X,city",
        "alice,X,NY",
        "# comment",
        "",
        "bob,X,LA",
        "carol,X",
      }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    end)

    it("deletes the delimiter of each row when `include_delimiter` is set", function()
      local co = coroutine.running()
      local bufnr = setup_buffer(lines, { include_delimiter = true }, opts)

      vim.api.nvim_win_set_cursor(0, { 2, 6 }) -- "20" of the age column
      testutil.feedkeys(co, "dic")

      assert.are.same({
        "name,age,city",
        "alice,NY",
        "# comment",
        "",
        "bob,LA",
        "carol", -- the last column takes the delimiter before it
      }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    end)

    it("places a cursor at the start of the field of each row", function()
      local co = coroutine.running()
      local bufnr = setup_buffer(lines, { include_delimiter = false }, opts)

      vim.api.nvim_win_set_cursor(0, { 2, 6 }) -- "20" of the age column
      testutil.feedkeys(co, "yic")

      -- The primary cursor covers row 2, the header row is excluded.
      assert.are.same({ { 5, 4 }, { 6, 6 } }, testutil.get_multicursors(bufnr))
      assert.are.same(lines, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    end)

    it("selects only the field under the cursor when invoked from visual mode", function()
      local co = coroutine.running()
      local bufnr = setup_buffer(lines, { include_delimiter = false }, opts)

      vim.api.nvim_win_set_cursor(0, { 2, 6 }) -- "20" of the age column
      -- Neovim replays a visual sequence as keys, and the selection of this text object
      -- cannot be replayed, so the other rows must not get a cursor here.
      testutil.feedkeys(co, "vicy")

      assert.are.same({}, testutil.get_multicursors(bufnr))
      assert.are.same("20", vim.fn.getreg('"'))
    end)

    it("re-targets the cursors when invoked on another column", function()
      local co = coroutine.running()
      local bufnr = setup_buffer(lines, { include_delimiter = false }, opts)

      vim.api.nvim_win_set_cursor(0, { 2, 6 }) -- "20" of the age column
      testutil.feedkeys(co, "yic")
      vim.api.nvim_win_set_cursor(0, { 2, 0 }) -- "alice" of the name column
      testutil.feedkeys(co, "cicX<Esc>")

      assert.are.same({
        "name,age,city",
        "X,20,NY",
        "# comment",
        "",
        "X,31,LA",
        "X,42",
      }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    end)

    it("does nothing on a comment line", function()
      local co = coroutine.running()
      local bufnr = setup_buffer(lines, { include_delimiter = false }, opts)

      vim.api.nvim_win_set_cursor(0, { 3, 0 })
      testutil.feedkeys(co, "cicX<Esc>")

      assert.are.same(lines, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
      assert.are.same({}, testutil.get_multicursors(bufnr))
    end)

    it("handles multi-line fields", function()
      local co = coroutine.running()
      local buflines = testutil.readlines("tests/fixtures/multiline.csv")
      local bufnr = setup_buffer(buflines, { include_delimiter = false }, {
        parser = { comments = { "#" }, delimiter = "," },
        view = { header_lnum = 2 },
      })

      vim.api.nvim_win_set_cursor(0, { 3, 4 }) -- `"John Doe"` of the Name column
      testutil.feedkeys(co, "cicX<Esc>")

      local result = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.are.same('1,X,"123 Main St', result[3])
      assert.are.same('2,X,"456 Oak Ave', result[10])
    end)
  end)
end)
