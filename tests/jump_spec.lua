---@diagnostic disable: await-in-sync
local config = require("csvview.config")
local csvview = require("csvview")
local jump = require("csvview.jump")

---@type CsvView.Options
local opts = { parser = { comments = { "#" } } }

local lines = {
  "Index,ID,Name,Email,Birthday",
  "1,XUMMW7737A,Jane Davis,jane.williams@example.org,1964-03-22",
  "# this is a comment",
  "",
  "last line",
}

---@class CsvView.MotionCase
---@field name string
---@field cursor { row: integer, col: integer } 1-based lnum and 0-based byte offset
---@field opts CsvView.JumpOpts
---@field expected_csv_cursor CsvView.Cursor csv cursor

---@type CsvView.MotionCase[]
local jump_cases = {
  {
    name = "to the next column",
    cursor = { row = 2, col = 0 },
    opts = { pos = { 0, 1 }, mode = "relative" },
    expected_csv_cursor = { kind = "field", pos = { 2, 2 }, anchor = "start", text = "XUMMW7737A" },
  },
  {
    name = "to the next row",
    cursor = { row = 1, col = 0 },
    opts = { pos = { 1, 0 }, mode = "relative" },
    expected_csv_cursor = { kind = "field", pos = { 2, 1 }, anchor = "start", text = "1" },
  },
  {
    name = "to the previous row",
    cursor = { row = 2, col = 0 },
    opts = { pos = { -1, 0 }, mode = "relative" },
    expected_csv_cursor = { kind = "field", pos = { 1, 1 }, anchor = "start", text = "Index" },
  },
  {
    name = "to the absolute position",
    cursor = { row = 3, col = 0 },
    opts = { pos = { 2, 2 }, mode = "absolute" },
    expected_csv_cursor = { kind = "field", pos = { 2, 2 }, anchor = "start", text = "XUMMW7737A" },
  },
  {
    name = "to the next end of the field",
    cursor = { row = 2, col = 0 },
    opts = { pos = { 0, 1 }, anchor = "end" },
    expected_csv_cursor = { kind = "field", pos = { 2, 2 }, anchor = "end", text = "XUMMW7737A" },
  },
  {
    name = "to the previous end of the field",
    cursor = { row = 1, col = 10 },
    opts = { pos = { 0, -1 }, anchor = "end" },
    expected_csv_cursor = { kind = "field", pos = { 1, 2 }, anchor = "end", text = "ID" },
  },
  {
    name = "beyond the last column with wrapping",
    cursor = { row = 1, col = string.len(lines[1]) },
    opts = { pos = { 0, 2 }, mode = "relative", col_wrap = true },
    expected_csv_cursor = { kind = "field", pos = { 2, 2 }, anchor = "start", text = "XUMMW7737A" },
  },
  {
    name = "before the first column with wrapping",
    cursor = { row = 2, col = 0 },
    opts = { pos = { 0, -2 }, mode = "relative", col_wrap = true },
    expected_csv_cursor = { kind = "field", pos = { 1, 4 }, anchor = "start", text = "Email" },
  },
  {
    name = "to the next row skipping the comment",
    cursor = { row = 2, col = 0 },
    opts = { pos = { 1, 0 }, mode = "relative" },
    expected_csv_cursor = { kind = "field", pos = { 5, 1 }, anchor = "start", text = "last line" },
  },
  {
    name = "to the previous row skipping the comment",
    cursor = { row = 5, col = 0 },
    opts = { pos = { -1, 0 }, mode = "relative" },
    expected_csv_cursor = { kind = "field", pos = { 2, 1 }, anchor = "start", text = "1" },
  },
  {
    name = "to the next field skipping the comment and empty line with wrapping",
    cursor = { row = 2, col = 0 },
    opts = { pos = { 1, 0 }, mode = "relative", col_wrap = true },
    expected_csv_cursor = { kind = "field", pos = { 5, 1 }, anchor = "start", text = "last line" },
  },
  {
    name = "to the previous field skipping the comment and empty line with wrapping",
    cursor = { row = 5, col = 0 },
    opts = { pos = { 0, -1 }, mode = "relative", col_wrap = true },
    expected_csv_cursor = { kind = "field", pos = { 2, 5 }, anchor = "start", text = "1964-03-22" },
  },
}

local helpers_case = {
  {
    name = "cursor is in the middle of the field",
    cursor = { row = 2, col = 4 },
    expected_csv_cursor = {
      next_field_start = {
        kind = "field",
        pos = { 2, 3 },
        anchor = "start",
        text = "Jane Davis",
      },
      prev_field_start = {
        kind = "field",
        pos = { 2, 2 },
        anchor = "start",
        text = "XUMMW7737A",
      },
      next_field_end = {
        kind = "field",
        pos = { 2, 2 },
        anchor = "end",
        text = "XUMMW7737A",
      },
      prev_field_end = {
        kind = "field",
        pos = { 2, 1 },
        anchor = "start",
        text = "1",
      },
    },
  },
  {
    name = "cursor is at the start of the field",
    cursor = { row = 2, col = 2 },
    expected_csv_cursor = {
      next_field_start = {
        kind = "field",
        pos = { 2, 3 },
        anchor = "start",
        text = "Jane Davis",
      },
      prev_field_start = {
        kind = "field",
        pos = { 2, 1 },
        anchor = "start",
        text = "1",
      },
      next_field_end = {
        kind = "field",
        pos = { 2, 2 },
        anchor = "end",
        text = "XUMMW7737A",
      },
      prev_field_end = {
        kind = "field",
        pos = { 2, 1 },
        anchor = "start",
        text = "1",
      },
    },
  },
  {
    name = "cursor is at the end of the field",
    cursor = { row = 2, col = string.len(lines[2]) },
    expected_csv_cursor = {
      next_field_start = {
        kind = "field",
        pos = { 5, 1 },
        anchor = "start",
        text = "last line",
      },
      prev_field_start = {
        kind = "field",
        pos = { 2, 5 },
        anchor = "start",
        text = "1964-03-22",
      },
      next_field_end = {
        kind = "field",
        pos = { 5, 1 },
        anchor = "end",
        text = "last line",
      },
      prev_field_end = {
        kind = "field",
        pos = { 2, 4 },
        anchor = "end",
        text = "jane.williams@example.org",
      },
    },
  },
  {
    name = "cursor is at the delimiter",
    cursor = { row = 2, col = 1 },
    expected_csv_cursor = {
      next_field_start = {
        kind = "field",
        pos = { 2, 2 },
        anchor = "start",
        text = "XUMMW7737A",
      },
      prev_field_start = {
        kind = "field",
        pos = { 2, 1 },
        anchor = "start",
        text = "1",
      },
      next_field_end = {
        kind = "field",
        pos = { 2, 2 },
        anchor = "end",
        text = "XUMMW7737A",
      },
      prev_field_end = {
        kind = "field",
        pos = { 2, 1 },
        anchor = "start",
        text = "1",
      },
    },
  },
  {
    name = "cursor is at comment line",
    cursor = { row = 3, col = 0 },
    expected_csv_cursor = {
      next_field_start = {
        kind = "field",
        pos = { 5, 1 },
        anchor = "start",
        text = "last line",
      },
      prev_field_start = {
        kind = "field",
        pos = { 2, 5 },
        anchor = "start",
        text = "1964-03-22",
      },
      next_field_end = {
        kind = "field",
        pos = { 5, 1 },
        anchor = "end",
        text = "last line",
      },
      prev_field_end = {
        kind = "field",
        pos = { 2, 5 },
        anchor = "end",
        text = "1964-03-22",
      },
    },
  },
  {
    name = "cursor is at empty line",
    cursor = { row = 4, col = 0 },
    expected_csv_cursor = {
      next_field_start = {
        kind = "field",
        pos = { 5, 1 },
        anchor = "start",
        text = "last line",
      },
      prev_field_start = {
        kind = "field",
        pos = { 2, 5 },
        anchor = "start",
        text = "1964-03-22",
      },
      next_field_end = {
        kind = "field",
        pos = { 5, 1 },
        anchor = "end",
        text = "last line",
      },
      prev_field_end = {
        kind = "field",
        pos = { 2, 5 },
        anchor = "end",
        text = "1964-03-22",
      },
    },
  },
}

describe("motion", function()
  before_each(function()
    config.setup()
    csvview.setup()
  end)

  describe("jump", function()
    for _, case in ipairs(jump_cases) do
      it(case.name, function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
        vim.api.nvim_win_set_buf(0, bufnr)

        csvview.enable(bufnr, opts)

        -- Move cursor to the specified field
        vim.api.nvim_win_set_cursor(0, { case.cursor.row, case.cursor.col })
        jump.field(bufnr, case.opts)

        -- Get the new cursor position
        local csv_cursor = require("csvview.util").get_cursor(bufnr)
        assert.are.same(case.expected_csv_cursor, csv_cursor)
      end)
    end
  end)

  local func_names = {
    "next_field_start",
    "prev_field_start",
    "next_field_end",
    "prev_field_end",
  }

  for _, func_name in ipairs(func_names) do
    for i = 1, #helpers_case do
      -- it(string.format("%s %s", func_name, helpers_case[i].name), function()
      it(string.format("%s should jump correctly when %s", func_name, helpers_case[i].name), function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
        vim.api.nvim_win_set_buf(0, bufnr)

        csvview.enable(bufnr, opts)

        -- Move cursor to the specified field
        vim.api.nvim_win_set_cursor(0, { helpers_case[i].cursor.row, helpers_case[i].cursor.col })

        jump[func_name](bufnr)
        -- Get the new cursor position
        local csv_cursor = require("csvview.util").get_cursor(bufnr)
        assert.are.same(helpers_case[i].expected_csv_cursor[func_name], csv_cursor)
      end)
    end
  end
end)
