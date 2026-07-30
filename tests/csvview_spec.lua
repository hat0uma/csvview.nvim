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
      csvview.setup({ parser = { comments = { "#" } } })
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

  describe("update", function()
    config.setup()
    csvview.setup()

    --- Enable csvview on a fresh buffer and return it.
    ---@param opts CsvView.Options?
    ---@return integer bufnr
    local function enabled_buf(opts)
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "name,age,city",
        "John,25,New York",
        "Jane,30,Los Angeles",
      })
      vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), bufnr)
      csvview.enable(bufnr, opts)
      vim.wait(50)
      return bufnr
    end

    it("should apply view options to the attached view", function()
      local bufnr = enabled_buf({ view = { display_mode = "highlight" } })
      csvview.update(bufnr, { view = { display_mode = "border" } })
      vim.wait(50)

      local view = require("csvview.view").get(bufnr)
      assert(view)
      assert.equals("border", view.opts.view.display_mode)
      assert.equals(2, vim.api.nvim_get_option_value("conceallevel", { win = 0, scope = "local" }))

      csvview.disable(bufnr)
    end)

    it("should re-parse when a parser option changes", function()
      local bufnr = enabled_buf({ parser = { delimiter = "," } })
      csvview.update(bufnr, { parser = { delimiter = ";" } })
      vim.wait(50)

      assert.is_true(csvview.is_enabled(bufnr))
      assert.equals(";", vim.b[bufnr].csvview_info.delimiter.text)

      -- The whole line is one field with the new delimiter.
      local view = require("csvview.view").get(bufnr)
      assert(view)
      assert.equals(1, view.metrics:row({ lnum = 1 }):field_count())

      csvview.disable(bufnr)
    end)

    it("should warn and do nothing when the buffer is not enabled", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local notified = false
      local notify = vim.notify
      vim.notify = function() ---@diagnostic disable-line: duplicate-set-field
        notified = true
      end

      csvview.update(bufnr, { view = { display_mode = "border" } })
      vim.notify = notify ---@diagnostic disable-line: duplicate-set-field

      assert.is_true(notified)
      assert.is_false(csvview.is_enabled(bufnr))
    end)
  end)
end)
