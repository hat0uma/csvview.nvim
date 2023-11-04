local config = require("csvview.config")
local p = require("csvview.parser")

describe("parser", function()
  describe("_parse_line", function()
    it("line without empty fields", function()
      assert.are.same({ "abc", "de", "f", "g", "h" }, p._parse_line("abc,de,f,g,h"))
    end)

    it("should works for line includes empty fields", function()
      assert.are.same({ "abc", "de", "", "g", "h" }, p._parse_line("abc,de,,g,h"))
      assert.are.same({ "abc", "de", "f", "g", "" }, p._parse_line("abc,de,f,g,"))
      assert.are.same({ "", "abc", "de", "f", "g" }, p._parse_line(",abc,de,f,g"))
      assert.are.same({ "abc", "f", "g", "", "" }, p._parse_line("abc,f,g,,"))
    end)

    it("empty line", function()
      assert.are.same({}, p._parse_line(""))
    end)
  end)

  describe("iter_lines_async", function()
    it("should parse all lines when no range is specified", function()
      local co = coroutine.running()
      local lines = {
        "a,b,c,d,e,,",
        "",
        "m,n",
      }
      local expected = {
        { "a", "b", "c", "d", "e", "", "" },
        {},
        { "m", "n" },
      }
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

      local actual = {}
      local opts = config.get({ parser = { async_chunksize = 1 } })
      p.iter_lines_async(buf, nil, nil, {
        on_line = function(_, line)
          table.insert(actual, line)
        end,
        on_end = vim.schedule_wrap(function()
          assert.are.same(expected, actual)
          coroutine.resume(co)
        end),
      }, opts)

      coroutine.yield()
    end)
    it("should parse only the specified range", function()
      local co = coroutine.running()
      local lines = {
        "a,b,c,d,e,,",
        "f,g,h,i,j,k,l",
        "",
        "m,n",
      }
      local startlnum = 2
      local endlnum = 3
      local expected = {
        { "f", "g", "h", "i", "j", "k", "l" },
        {},
      }
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

      local actual = {}
      p.iter_lines_async(buf, startlnum, endlnum, {
        on_line = function(_, line)
          table.insert(actual, line)
        end,
        on_end = vim.schedule_wrap(function()
          assert.are.same(expected, actual)
          coroutine.resume(co)
        end),
      }, config.defaults)

      coroutine.yield()
    end)
  end)
end)
