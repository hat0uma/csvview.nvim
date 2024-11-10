local config = require("csvview.config")
local p = require("csvview.parser")

describe("parser", function()
  config.setup()

  local delim = ","
  local delim_byte = string.byte(delim)

  describe("_parse_line", function()
    it("line without empty fields", function()
      assert.are.same({ "abc", "de", "f", "g", "h" }, p._parse_line("abc,de,f,g,h", delim_byte))
    end)

    it("should works for line includes empty fields", function()
      assert.are.same({ "abc", "de", "", "g", "h" }, p._parse_line("abc,de,,g,h", delim_byte))
      assert.are.same({ "abc", "de", "f", "g", "" }, p._parse_line("abc,de,f,g,", delim_byte))
      assert.are.same({ "", "abc", "de", "f", "g" }, p._parse_line(",abc,de,f,g", delim_byte))
      assert.are.same({ "abc", "f", "g", "", "" }, p._parse_line("abc,f,g,,", delim_byte))
    end)

    it("empty line", function()
      assert.are.same({}, p._parse_line("", delim_byte))
    end)
    it("should works for line includes quoted comma.", function()
      assert.are.same({ "abc", "de", '"f,g"', "h" }, p._parse_line('abc,de,"f,g",h', delim_byte))
    end)
    it("handles fields with missing closing quotes", function()
      assert.are.same({ "abc", "de", '"f,g,h' }, p._parse_line('abc,de,"f,g,h', delim_byte))
    end)

    it("parses tab-delimited lines correctly", function()
      local delim = "\t"
      local delim_byte = string.byte(delim)
      assert.are.same({ "abc", "de", "f", "g", "h" }, p._parse_line("abc\tde\tf\tg\th", delim_byte))
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
      local opts = config.get({ parser = { async_chunksize = 1, delimiter = delim } })
      p.iter_lines_async(buf, nil, nil, {
        on_line = function(_, is_comment, line)
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
        on_line = function(_, is_comment, line)
          table.insert(actual, line)
        end,
        on_end = vim.schedule_wrap(function()
          assert.are.same(expected, actual)
          coroutine.resume(co)
        end),
      }, config.defaults)

      coroutine.yield()
    end)

    it("should ignore comment lines", function()
      local co = coroutine.running()
      local lines = {
        "a,b,c,d,e,,",
        "# this is a comment",
        "f,g,h,i,j,k,l",
        "",
        "m,n",
      }
      local expected = {
        { is_comment = false, fields = { "a", "b", "c", "d", "e", "", "" } },
        { is_comment = true, fields = {} },
        { is_comment = false, fields = { "f", "g", "h", "i", "j", "k", "l" } },
        { is_comment = false, fields = {} },
        { is_comment = false, fields = { "m", "n" } },
      }
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

      local opts = config.get({ parser = { comments = { "#" } } })

      local actual = {}
      p.iter_lines_async(buf, nil, nil, {
        on_line = function(_, is_comment, line)
          table.insert(actual, { is_comment = is_comment, fields = line })
        end,
        on_end = vim.schedule_wrap(function()
          assert.are.same(expected, actual)
          coroutine.resume(co)
        end),
      }, opts)

      coroutine.yield()
    end)
  end)
end)
