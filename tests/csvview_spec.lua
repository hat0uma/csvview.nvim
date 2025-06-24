---@diagnostic disable: await-in-sync
local config = require("csvview.config")
local csvview = require("csvview")
local testutil = require("tests.testutil")

describe("csvview", function()
  describe("enable should align correctly even if it contains multibyte characters", function()
    config.setup()
    csvview.setup()
    local ns = vim.api.nvim_get_namespaces()["csv_extmark"]
    local cases = require("tests.cases.enable")
    for _, case in ipairs(cases) do
      it(case.name, function()
        -- create buffer and set lines
        local bufnr = vim.api.nvim_create_buf(false, true)
        local opts = config.get(case.opts)
        local lines = case.lines
        local expected = case.expected
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

        -- set buffer to current window
        local winid = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(winid, bufnr)

        -- compute metrics
        local co = coroutine.running()
        csvview.enable(bufnr, opts)

        -- wait for the completion of the metrics computation
        testutil.yield_next_loop(co)

        -- check the result
        local actual = testutil.get_lines_with_extmarks(bufnr, ns)
        for i, line in ipairs(actual) do
          assert.are.same(expected[i], line)
        end
      end)
    end
  end)

  --- Run update tests for csvview.
  ---@param tests { describe: string, cases: CsvView.Tests.UpdateCase[] }[]
  local function run_update_tests(tests)
    describe("when updating the buffer", function()
      config.setup({ parser = { comments = { "#" } } })
      csvview.setup()
      local ns = vim.api.nvim_get_namespaces()["csv_extmark"]

      for _, section in ipairs(tests) do
        describe(section.describe, function()
          for _, case in ipairs(section.cases) do
            it(case.name, function()
              -- create buffer and set lines
              local bufnr = vim.api.nvim_create_buf(false, true)
              local opts = config.get(case.opts)
              local lines = case.lines
              local expected = case.expected
              vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

              -- set buffer to current window
              local winid = vim.api.nvim_get_current_win()
              vim.api.nvim_win_set_buf(winid, bufnr)

              -- compute metrics
              local co = coroutine.running()
              csvview.enable(bufnr, opts)

              -- wait for the completion of the metrics computation
              testutil.yield_next_loop(co)

              -- change line
              for _, change in ipairs(case.changes) do
                if change.type == "modify" then
                  vim.api.nvim_buf_set_lines(bufnr, change.line - 1, change.line, false, { change.after })
                elseif change.type == "delete" then
                  vim.api.nvim_buf_set_lines(bufnr, change.line - 1, change.line, true, {})
                elseif change.type == "insert" then
                  vim.api.nvim_buf_set_lines(bufnr, change.line - 1, change.line - 1, false, { change.after })
                end
                testutil.yield_next_loop(co)
              end

              vim.cmd([[ redraw! ]])

              -- check the result
              local actual = testutil.get_lines_with_extmarks(bufnr, ns)
              -- for i, line in ipairs(actual) do
              --   print(line)
              -- end
              for i, line in ipairs(actual) do
                assert.are.same(expected[i], line)
              end
            end)
          end
        end)
      end
    end)
  end
  run_update_tests(require("tests.cases.buffer_update"))
  run_update_tests(require("tests.cases.buffer_update_multiline"))
end)
