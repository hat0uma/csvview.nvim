---@diagnostic disable: await-in-sync
local config = require("csvview.config")
local csvview = require("csvview")
local jump = require("csvview.jump")
local testutil = require("tests.testutil")

---@type CsvView.Options
local opts = { parser = { comments = { "#" } } }

local lines = testutil.readlines("tests/fixtures/minimal.csv")

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

local multiline_lines = testutil.readlines("tests/fixtures/multiline.csv")

---@type CsvView.MotionCase[]
local multiline_jump_cases = {
  {
    name = "from start of multiline field to next field",
    cursor = { row = 3, col = 13 }, -- Start of Address field
    opts = { pos = { 0, 1 }, mode = "relative" },
    expected_csv_cursor = {
      kind = "field",
      pos = { 3, 4 },
      anchor = "start",
      text = '"Customer since 2020\nPrefers email contact\nHas special delivery instructions:\n- Ring doorbell twice\n- Leave package at door"',
    },
  },
  {
    name = "from middle of multiline field to next field",
    cursor = { row = 5, col = 5 }, -- Middle of Address field
    opts = { pos = { 0, 1 }, mode = "relative" },
    expected_csv_cursor = {
      kind = "field",
      pos = { 3, 4 },
      anchor = "start",
      text = '"Customer since 2020\nPrefers email contact\nHas special delivery instructions:\n- Ring doorbell twice\n- Leave package at door"',
    },
  },
  {
    name = "from end of multiline field to next row",
    cursor = { row = 9, col = 0 }, -- End of first record
    opts = { pos = { 1, 0 }, mode = "relative" },
    expected_csv_cursor = {
      kind = "field",
      pos = { 4, 4 },
      anchor = "start",
      text = table.concat({
        '"VIP customer',
        "Priority shipping",
        "Contact: jane@example.com",
        "Notes:",
        "- Allergic to latex",
        '- Prefers eco-friendly packaging"',
      }, "\n"),
    },
  },
  {
    name = "to absolute position in multiline context",
    cursor = { row = 2, col = 0 },
    opts = { pos = { 3, 3 }, mode = "absolute" },
    expected_csv_cursor = {
      kind = "field",
      pos = { 3, 3 },
      anchor = "start",
      text = '"123 Main St\nApt 4B\nNew York, NY 10001"',
    },
  },
  {
    name = "navigate between multiline fields with wrapping",
    cursor = { row = 9, col = 0 }, -- End of Notes field
    opts = { pos = { 0, 1 }, mode = "relative", col_wrap = true },
    expected_csv_cursor = { kind = "field", pos = { 4, 1 }, anchor = "start", text = "2" },
  },
  {
    name = "navigate to end of multiline field",
    cursor = { row = 3, col = 13 }, -- Start of Address field
    opts = { pos = { 0, 0 }, anchor = "end" },
    expected_csv_cursor = {
      kind = "field",
      pos = { 3, 3 },
      anchor = "end",
      text = '"123 Main St\nApt 4B\nNew York, NY 10001"',
    },
  },
  {
    name = "when jumping beyond the last field, limit the range",
    cursor = { row = #multiline_lines - 1, col = 0 }, -- Last field
    opts = { pos = { 0, 1 }, mode = "relative", col_wrap = true },
    expected_csv_cursor = {
      kind = "field",
      pos = { 4, 4 },
      anchor = "start",
      text = table.concat({
        '"VIP customer',
        "Priority shipping",
        "Contact: jane@example.com",
        "Notes:",
        "- Allergic to latex",
        '- Prefers eco-friendly packaging"',
      }, "\n"),
    },
  },
  {
    name = "when jumping beyond the first field, limit the range",
    cursor = { row = 2, col = 0 }, -- First field
    opts = { pos = { 0, -1 }, mode = "relative", col_wrap = true },
    expected_csv_cursor = {
      kind = "field",
      pos = { 2, 1 },
      anchor = "start",
      text = "ID",
    },
  },
}

local multiline_helpers_case = {
  {
    name = "cursor is in the middle of multiline field",
    cursor = { row = 5, col = 5 }, -- Middle of Address field
    expected_csv_cursor = {
      next_field_start = {
        kind = "field",
        pos = { 3, 4 },
        anchor = "start",
        text = '"Customer since 2020\nPrefers email contact\nHas special delivery instructions:\n- Ring doorbell twice\n- Leave package at door"',
      },
      prev_field_start = {
        kind = "field",
        pos = { 3, 3 },
        anchor = "start",
        text = '"123 Main St\nApt 4B\nNew York, NY 10001"',
      },
      next_field_end = {
        kind = "field",
        pos = { 3, 3 },
        anchor = "end",
        text = '"123 Main St\nApt 4B\nNew York, NY 10001"',
      },
      prev_field_end = {
        kind = "field",
        pos = { 3, 2 },
        anchor = "end",
        text = '"John Doe"',
      },
    },
  },
  {
    name = "cursor is at start of multiline field",
    cursor = { row = 3, col = 13 }, -- Start of Address field
    expected_csv_cursor = {
      next_field_start = {
        kind = "field",
        pos = { 3, 4 },
        anchor = "start",
        text = '"Customer since 2020\nPrefers email contact\nHas special delivery instructions:\n- Ring doorbell twice\n- Leave package at door"',
      },
      prev_field_start = {
        kind = "field",
        pos = { 3, 2 },
        anchor = "start",
        text = '"John Doe"',
      },
      next_field_end = {
        kind = "field",
        pos = { 3, 3 },
        anchor = "end",
        text = '"123 Main St\nApt 4B\nNew York, NY 10001"',
      },
      prev_field_end = {
        kind = "field",
        pos = { 3, 2 },
        anchor = "end",
        text = '"John Doe"',
      },
    },
  },
  {
    name = "cursor is at end of multiline field",
    cursor = { row = 9, col = 23 }, -- End of Notes field
    expected_csv_cursor = {
      next_field_start = {
        kind = "field",
        pos = { 4, 1 },
        anchor = "start",
        text = "2",
      },
      prev_field_start = {
        kind = "field",
        pos = { 3, 4 },
        anchor = "start",
        text = '"Customer since 2020\nPrefers email contact\nHas special delivery instructions:\n- Ring doorbell twice\n- Leave package at door"',
      },
      next_field_end = {
        kind = "field",
        pos = { 4, 1 },
        anchor = "start",
        text = "2",
      },
      prev_field_end = {
        kind = "field",
        pos = { 3, 3 },
        anchor = "end",
        text = '"123 Main St\nApt 4B\nNew York, NY 10001"',
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

  describe("jump with multiline fields", function()
    for _, case in ipairs(multiline_jump_cases) do
      it(case.name, function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, multiline_lines)
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

  for _, func_name in ipairs(func_names) do
    for i = 1, #multiline_helpers_case do
      it(
        string.format(
          "%s should jump correctly in multiline context when %s",
          func_name,
          multiline_helpers_case[i].name
        ),
        function()
          local bufnr = vim.api.nvim_create_buf(false, true)
          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, multiline_lines)
          vim.api.nvim_win_set_buf(0, bufnr)

          csvview.enable(bufnr, opts)

          -- Move cursor to the specified field
          vim.api.nvim_win_set_cursor(0, { multiline_helpers_case[i].cursor.row, multiline_helpers_case[i].cursor.col })

          jump[func_name](bufnr)
          -- Get the new cursor position
          local csv_cursor = require("csvview.util").get_cursor(bufnr)
          assert.are.same(multiline_helpers_case[i].expected_csv_cursor[func_name], csv_cursor)
        end
      )
    end
  end
end)
