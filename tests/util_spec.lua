---@diagnostic disable: await-in-sync
local csvview = require("csvview")
local testutil = require("tests.testutil")
local util = require("csvview.util")

--- Create test cases
---@param delimiter string
---@return CsvView.Options, string[], { name:string, cases:{ name:string, cursor:integer[],expected:CsvView.Cursor}[] }[]
local function create_test(delimiter)
  local opts = {
    parser = {
      delimiter = delimiter,
      quote_char = '"',
      comments = { "#" },
    },
    view = {},
  }

  local lines = {
    "# Comment line",
    "field1",
    "",
    table.concat({ "field2", "field3", "field4" }, delimiter),
    table.concat({ "🥰abc", "a😊c", "abc😎" }, delimiter),
  }

  local cases = {
    {
      name = "should return comment cursor",
      cases = {
        {
          name = "at the start of the comment",
          cursor = { 1, 0 },
          expected = { kind = "comment", pos = { 1 } },
        },
        {
          name = "at the end of the comment",
          cursor = { 1, #lines[1] - 1 },
          expected = { kind = "comment", pos = { 1 } },
        },
      },
    },
    {
      name = "should return field cursor",
      cases = {
        {
          name = "at the start of the field",
          cursor = { 2, 0 },
          expected = {
            kind = "field",
            pos = { 2, 1 },
            anchor = "start",
            text = "field1",
          },
        },
        {
          name = "inside the field",
          cursor = { 2, #lines[2] - 2 },
          expected = {
            kind = "field",
            pos = { 2, 1 },
            anchor = "inside",
            text = "field1",
          },
        },
        {
          name = "at the end of the field",
          cursor = { 2, #lines[2] - 1 },
          expected = {
            kind = "field",
            pos = { 2, 1 },
            anchor = "end",
            text = "field1",
          },
        },
        {
          name = "at the delimiter",
          cursor = { 4, string.len("field2") + #delimiter - 1 },
          expected = {
            kind = "field",
            pos = { 4, 1 },
            anchor = "delimiter",
            text = "field2",
          },
        },
      },
    },
    {
      name = "should return empty line cursor",
      cases = {
        {
          name = "",
          cursor = { 3, 0 },
          expected = {
            kind = "empty_line",
            pos = { 3 },
          },
        },
      },
    },
    {
      name = "should return field cursor with multibyte characters",
      cases = {
        {
          name = "at the start of the field",
          cursor = { 5, 0 },
          expected = {
            kind = "field",
            pos = { 5, 1 },
            anchor = "start",
            text = "🥰abc",
          },
        },
        {
          name = "inside the field",
          cursor = { 5, string.len(string.format("🥰abc%sa😊", delimiter)) - 2 },
          expected = {
            kind = "field",
            pos = { 5, 2 },
            anchor = "inside",
            text = "a😊c",
          },
        },
        {
          name = "at the end of the field",
          cursor = { 5, string.len(string.format("🥰abc%sa😊c%sabc😎", delimiter, delimiter)) - 1 },
          expected = {
            kind = "field",
            pos = { 5, 3 },
            anchor = "end",
            text = "abc😎",
          },
        },
        {
          name = "at the delimiter",
          cursor = { 5, string.len("🥰abc" .. delimiter) - 1 },
          expected = {
            kind = "field",
            pos = { 5, 1 },
            anchor = "delimiter",
            text = "🥰abc",
          },
        },
      },
    },
  }

  return opts, lines, cases
end

--- Run test cases
--- @param opts CsvView.Options
--- @param lines string[]
--- @param cases { name:string, cases:{ name:string, cursor:integer[],expected:CsvView.Cursor}[] }[]
local function run(opts, lines, cases)
  describe(string.format("get_cursor (delimiter=%s)", opts.parser.delimiter), function()
    csvview.setup(opts)
    -- create buffer and set lines
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

    -- set buffer to current window
    local winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(winid, bufnr)

    -- compute metrics
    local co = coroutine.running()
    csvview.enable(bufnr, opts)

    -- wait for the completion of the metrics computation
    testutil.yield_next_loop(co)

    for _, c in ipairs(cases) do
      describe(c.name, function()
        for _, cc in ipairs(c.cases) do
          it(cc.name, function()
            vim.api.nvim_win_set_cursor(0, cc.cursor)
            local cursor = util.get_cursor()
            assert.are.same(cc.expected, cursor)
          end)
        end
      end)
    end
  end)
end

describe("util", function()
  run(create_test(","))
  run(create_test("|||||"))

  describe("get_cursor (multi-line)", function()
    ---@type CsvView.Options
    local opts = {
      parser = {
        delimiter = ",",
        quote_char = '"',
        comments = { "#" },
      },
      view = {},
    }

    ---@type { name:string, cursor:integer[],expected:CsvView.Cursor}[] }[]
    local multiline_cases = {
      {
        name = "cursor at start of multi-line field",
        cursor = { 3, 13 }, -- Start of address field
        expected = {
          kind = "field",
          pos = { 3, 3 },
          anchor = "start",
          text = '"123 Main St\nApt 4B\nNew York, NY 10001"',
        },
      },
      {
        name = "cursor in middle of multi-line field",
        cursor = { 4, 5 }, -- Middle of address field
        expected = {
          kind = "field",
          pos = { 3, 3 },
          anchor = "inside",
          text = '"123 Main St\nApt 4B\nNew York, NY 10001"',
        },
      },
      {
        name = "cursor at end of multi-line field",
        cursor = { 5, 18 }, -- End of address field
        expected = {
          kind = "field",
          pos = { 3, 3 },
          anchor = "end",
          text = '"123 Main St\nApt 4B\nNew York, NY 10001"',
        },
      },
      {
        name = "cursor at delimiter after multi-line field",
        cursor = { 5, 19 }, -- Delimiter after address field
        expected = {
          kind = "field",
          pos = { 3, 3 },
          anchor = "delimiter",
          text = '"123 Main St\nApt 4B\nNew York, NY 10001"',
        },
      },
    }

    --- Run multi-line cursor test cases
    ---@param cases { name:string, cursor:integer[],expected:CsvView.Cursor}[] }[]
    local function run_multiline_tests(cases)
      csvview.setup(opts)

      for _, case in ipairs(cases) do
        it(case.name, function()
          local lines = testutil.readlines("tests/fixtures/multiline.csv")
          local bufnr = vim.api.nvim_create_buf(false, true)
          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

          local winid = vim.api.nvim_get_current_win()
          vim.api.nvim_win_set_buf(winid, bufnr)

          local co = coroutine.running()
          csvview.enable(bufnr, opts)
          testutil.yield_next_loop(co)

          vim.api.nvim_win_set_cursor(0, case.cursor)
          local cursor = util.get_cursor(bufnr)
          assert.are.same(case.expected, cursor)
        end)
      end
    end

    run_multiline_tests(multiline_cases)
  end)
end)
