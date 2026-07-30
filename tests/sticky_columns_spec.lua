---@diagnostic disable: await-in-sync
local config = require("csvview.config")
local csvview = require("csvview")

---@class CsvView.Tests.StickyColumnsCase
---@field name string
---@field winview vim.fn.winrestview.dict
---@field winopts? { [1]: string, [2]: any }[]
---@field opts CsvView.Options
---@field assert fun(case: CsvView.Tests.StickyColumnsCase)

---@param role? "columns"|"corner"
local function get_sticky_columns_win(role)
  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.w[winid].csvview_sticky_columns_win == (role or "columns") then
      return winid
    end
  end

  return nil
end

local function should_show_sticky_columns()
  assert.are.not_nil(get_sticky_columns_win(), "Sticky columns window should be opened")
end

local function should_not_show_sticky_columns()
  assert.are_nil(get_sticky_columns_win(), "Sticky columns window should not be opened")
end

describe("sticky_columns", function()
  before_each(function()
    config.setup()
    csvview.setup()
  end)

  ---@type CsvView.Tests.StickyColumnsCase[]
  local cases = {
    {
      name = "does not show when the sticky_columns option is disabled",
      winview = { topline = 10, lnum = 15, leftcol = 20, col = 40 },
      opts = { view = { sticky_columns = { enabled = false, count = 1 } } },
      assert = should_not_show_sticky_columns,
    },
    {
      name = "does not show when nothing is scrolled out of view",
      winview = { topline = 10, lnum = 15, leftcol = 0, col = 0 },
      opts = { view = { sticky_columns = { enabled = true, count = 1 } } },
      assert = should_not_show_sticky_columns,
    },
    {
      name = "shows when the window is scrolled horizontally",
      winview = { topline = 10, lnum = 15, leftcol = 20, col = 40 },
      winopts = { { "sidescrolloff", 0 }, { "scrolloff", 0 } },
      opts = { view = { sticky_columns = { enabled = true, count = 1 } } },
      assert = should_show_sticky_columns,
    },
    {
      name = "syncs with the current window vertical scroll and pins leftcol at 0",
      winview = { topline = 10, lnum = 15, leftcol = 20, col = 40 },
      winopts = { { "sidescrolloff", 0 }, { "scrolloff", 0 } },
      opts = { view = { sticky_columns = { enabled = true, count = 1 } } },
      assert = function(case)
        local winid = get_sticky_columns_win()
        assert.are.not_nil(winid)
        assert(winid) -- suppress luals check

        local winview = vim.api.nvim_win_call(winid, vim.fn.winsaveview) ---@type vim.fn.winsaveview.ret
        assert.are.equal(case.winview.topline, winview.topline)
        assert.are.equal(0, winview.leftcol)
      end,
    },
    {
      name = "widens the overlay for more pinned columns",
      winview = { topline = 10, lnum = 15, leftcol = 40, col = 60 },
      winopts = { { "sidescrolloff", 0 }, { "scrolloff", 0 } },
      opts = { view = { sticky_columns = { enabled = true, count = 2 } } },
      assert = function()
        local winid = get_sticky_columns_win()
        assert.are.not_nil(winid)
        assert(winid) -- suppress luals check

        local view = require("csvview.view").get(vim.api.nvim_get_current_buf())
        assert.are.not_nil(view)
        assert(view) -- suppress luals check

        assert.are.equal(view:pinned_width(2), vim.api.nvim_win_get_width(winid))
        assert.is_true(view:pinned_width(2) > view:pinned_width(1))
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
      vim.api.nvim_set_option_value(opt[1], opt[2], { win = winid, scope = "local" })
    end

    it(case.name, function()
      -- Enable csvview first: the pinned width depends on the computed metrics.
      local bufnr = vim.api.nvim_get_current_buf()
      csvview.enable(bufnr, case.opts)
      vim.wait(50)

      vim.fn.winrestview(case.winview)
      vim.wait(1)
      require("csvview.sticky_columns").redraw()
      vim.wait(20) -- overlay windows are closed on the scheduler

      case.assert(case)

      -- Cleanup
      csvview.disable(bufnr)
      vim.wait(20)
    end)

    -- Clear window options
    for _, opt in ipairs(case.winopts or {}) do
      vim.api.nvim_set_option_value(opt[1], nil, { win = winid, scope = "local" })
    end
  end

  it("draws a separator at the right edge when configured", function()
    local bufnr = vim.api.nvim_get_current_buf()
    csvview.enable(bufnr, { view = { sticky_columns = { enabled = true, count = 1, separator = "." } } })
    vim.wait(50)

    vim.fn.winrestview({ topline = 10, lnum = 15, leftcol = 40, col = 60 })
    require("csvview.sticky_columns").redraw()
    vim.wait(20)

    local winid = get_sticky_columns_win()
    assert(winid)
    local border = vim.api.nvim_win_get_config(winid).border
    assert.are.same({ ".", "CsvViewStickyColumnsSeparator" }, border[4])

    csvview.disable(bufnr)
    vim.wait(20)
  end)

  it("reserves and restores 'sidescrolloff'", function()
    local winid = vim.api.nvim_get_current_win()
    vim.api.nvim_set_option_value("sidescrolloff", 3, { win = winid, scope = "local" })

    local bufnr = vim.api.nvim_get_current_buf()
    csvview.enable(bufnr, { view = { sticky_columns = { enabled = true, count = 1 } } })
    vim.wait(50)
    require("csvview.sticky_columns").redraw()
    vim.wait(20)

    local view = require("csvview.view").get(bufnr)
    assert(view)
    local expected = view:pinned_width(1) + 1
    assert.are.equal(expected, vim.api.nvim_get_option_value("sidescrolloff", { win = winid, scope = "local" }))

    csvview.disable(bufnr)
    vim.wait(20)
    assert.are.equal(3, vim.api.nvim_get_option_value("sidescrolloff", { win = winid, scope = "local" }))
  end)

  it("CsvViewStickyColumns retunes an attached view", function()
    vim.cmd("runtime! plugin/csvview.lua") -- tests run with --noplugin
    local bufnr = vim.api.nvim_get_current_buf()
    csvview.enable(bufnr, { view = { sticky_columns = { enabled = false, count = 1 } } })
    vim.wait(50)

    vim.fn.winrestview({ topline = 10, lnum = 15, leftcol = 40, col = 60 })
    vim.cmd("CsvViewStickyColumns 2")
    vim.wait(20)
    should_show_sticky_columns()

    local view = require("csvview.view").get(bufnr)
    assert(view)
    assert.are.equal(2, view.opts.view.sticky_columns.count)

    vim.cmd("CsvViewStickyColumns 0")
    vim.wait(20)
    should_not_show_sticky_columns()

    csvview.disable(bufnr)
  end)
end)
