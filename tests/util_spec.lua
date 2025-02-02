---@diagnostic disable: await-in-sync
local csvview = require("csvview")
local testutil = require("tests.testutil")
local util = require("csvview.util")

local opts = {
  parser = {
    delimiter = ",",
    quote_char = '"',
    comments = { "#" },
  },
  view = {},
}

local lines = {
  "# Comment line",
  "field1",
  "",
  "field2,field3,field4",
  "🥰abc,a😊c,abc😎",
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
        cursor = { 1, 14 },
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
        cursor = { 2, 4 },
        expected = {
          kind = "field",
          pos = { 2, 1 },
          anchor = "inside",
          text = "field1",
        },
      },
      {
        name = "at the end of the field",
        cursor = { 2, 5 },
        expected = {
          kind = "field",
          pos = { 2, 1 },
          anchor = "end",
          text = "field1",
        },
      },
      {
        name = "at the delimiter",
        cursor = { 4, 6 },
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
        cursor = { 5, string.len("🥰abc,a😊") - 1 },
        expected = {
          kind = "field",
          pos = { 5, 2 },
          anchor = "inside",
          text = "a😊c",
        },
      },
      {
        name = "at the end of the field",
        cursor = { 5, string.len("🥰abc,a😊c,abc😎") - 1 },
        expected = {
          kind = "field",
          pos = { 5, 3 },
          anchor = "end",
          text = "abc😎",
        },
      },
      {
        name = "at the delimiter",
        cursor = { 5, string.len("🥰abc,") - 1 },
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

describe("util", function()
  csvview.setup(opts)

  describe("get_cursor", function()
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
end)
