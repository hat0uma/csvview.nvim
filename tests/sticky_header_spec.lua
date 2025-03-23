---@diagnostic disable: await-in-sync
local config = require("csvview.config")
local csvview = require("csvview")

---@class CsvView.Tests.StickyHeaderCase
---@field name string
---@field winview vim.fn.winrestview.dict
---@field winopts? { [1]: string, [2]: any }[]
---@field opts CsvView.Options
---@field assert fun(case: CsvView.Tests.StickyHeaderCase)

local function get_sticky_header_win()
  local wins = vim.api.nvim_tabpage_list_wins(0)
  for _, winid in ipairs(wins) do
    if vim.w[winid].csvview_sticky_header_win then
      return winid
    end
  end

  return nil
end

local function should_show_sticky_header()
  assert.are.not_nil(get_sticky_header_win(), "Sticky header window should be opened")
end

local function should_not_show_sticky_header()
  assert.are_nil(get_sticky_header_win(), "Sticky header window should not be opened")
end

describe("sticky_header", function()
  before_each(function()
    config.setup()
    csvview.setup()
  end)

  ---@type CsvView.Tests.StickyHeaderCase[]
  local cases = {
    {
      name = "does not show when the sticky_header option is disabled",
      winview = { lnum = 100, col = 0 },
      opts = { view = { sticky_header = { enabled = false, separator = "-" }, header_lnum = 1 } },
      assert = should_not_show_sticky_header,
    },
    {
      name = "does not show when the header line is not set",
      winview = { lnum = 100, col = 0 },
      opts = { view = { sticky_header = { enabled = true, separator = "-" } } },
      assert = should_not_show_sticky_header,
    },
    {
      name = "does not show when the header is in the window",
      winview = { topline = 1, lnum = 5, col = 0 },
      opts = { view = { sticky_header = { enabled = true, separator = "-" }, header_lnum = 1 } },
      assert = should_not_show_sticky_header,
    },
    {
      name = "hides when the cursor overlaps with the header drawing position",
      winview = { topline = 10, lnum = 10, col = 0 },
      opts = { view = { sticky_header = { enabled = true, separator = "-" }, header_lnum = 1 } },
      assert = should_not_show_sticky_header,
    },
    {
      name = "hides when the cursor overlaps with the separator",
      winview = { topline = 10, lnum = 11, col = 0 },
      opts = { view = { sticky_header = { enabled = true, separator = "-" }, header_lnum = 5 } },
      assert = should_not_show_sticky_header,
    },
    {
      name = "shows when the header is out of the window",
      winview = { topline = 10, lnum = 11, col = 0 },
      opts = { view = { sticky_header = { enabled = true, separator = false }, header_lnum = 5 } },
      assert = should_show_sticky_header,
    },
    {
      name = "syncs with the current window horizontal scroll",
      winview = { topline = 10, lnum = 15, leftcol = 2, col = 2 },
      winopts = { { "sidescrolloff", 0 }, { "scrolloff", 0 } },
      opts = { view = { sticky_header = { enabled = true, separator = false }, header_lnum = 5 } },
      assert = function(case)
        local winid = get_sticky_header_win()
        assert.are.not_nil(winid)
        assert(winid) -- suppress luals check

        local winview = vim.api.nvim_win_call(winid, vim.fn.winsaveview) ---@type vim.fn.winsaveview.ret
        assert.are.equal(case.winview.leftcol, winview.leftcol)
        assert.are.equal(case.opts.view.header_lnum, winview.lnum)
      end,
    },
    {
      name = "computes the correct gutter column when statuscolumn is set",
      winview = { topline = 10, lnum = 15, col = 2 },
      winopts = {
        { "statuscolumn", "abc%{v:lnum}def" },
      },
      opts = { view = { sticky_header = { enabled = true, separator = false }, header_lnum = 5 } },
      assert = function(case)
        local winid = get_sticky_header_win()
        assert.are.not_nil(winid)

        -- Evaluate the statusline
        local statuscolumn = vim.wo[winid].statuscolumn
        local e = vim.api.nvim_eval_statusline(statuscolumn, {
          winid = winid,
          use_statuscol_lnum = case.opts.view.header_lnum,
          fillchar = " ",
        })

        local expected = string.format("abc%ddef", case.opts.view.header_lnum)
        assert.are.equal(expected, e.str)
      end,
    },
    {
      name = "computes the correct gutter column when no statuscolumn is set",
      winview = { topline = 10, lnum = 15, col = 2 },
      winopts = {
        { "number", true },
        { "relativenumber", true },
        { "numberwidth", 4 },
        { "signcolumn", "no" },
        { "foldcolumn", "0" },
        { "statuscolumn", nil },
      },
      opts = { view = { sticky_header = { enabled = true, separator = false }, header_lnum = 1 } },
      assert = function(case)
        local winid = get_sticky_header_win()
        assert.are.not_nil(winid)

        -- Evaluate the statusline
        local statuscolumn = vim.wo[winid].statuscolumn
        local e = vim.api.nvim_eval_statusline(statuscolumn, {
          winid = winid,
          use_statuscol_lnum = case.opts.view.header_lnum,
          fillchar = " ",
        })

        -- relativenumber is calculated based on the current cursor position
        local relnum = case.winview.lnum - case.opts.view.header_lnum
        local expected = string.format("%" .. (vim.wo[winid].numberwidth - 1) .. "d ", relnum)
        assert.are.equal(expected, e.str)
      end,
    },
  }

  vim.cmd.edit("tests/fixtures/test.csv")
  for _, case in ipairs(cases) do
    if csvview.is_enabled(0) then
      csvview.disable(0)
    end

    -- Set the window options
    local winid = vim.api.nvim_get_current_win()
    for _, opt in ipairs(case.winopts or {}) do
      local name = opt[1]
      local value = opt[2]
      vim.api.nvim_set_option_value(name, value, { win = winid, scope = "local" })
    end

    it(case.name, function()
      vim.fn.winrestview(case.winview)
      vim.wait(1)

      -- Enable csvview
      local bufnr = vim.api.nvim_get_current_buf()
      csvview.enable(bufnr, case.opts)
      vim.wait(1)

      -- Evaluate the expected result
      case.assert(case)

      -- Cleanup
      csvview.disable(bufnr)
    end)

    -- Clear window options
    for _, opt in ipairs(case.winopts or {}) do
      local name = opt[1]
      vim.api.nvim_set_option_value(name, nil, { win = winid, scope = "local" })
    end
  end
end)
