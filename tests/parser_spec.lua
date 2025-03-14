---@diagnostic disable: await-in-sync

local config = require("csvview.config")
local p = require("csvview.parser")

describe("parser", function()
  config.setup()

  local quote_char = '"'
  local quote_char_byte = string.byte(quote_char)

  describe("_parse_line", function()
    local opts = config.get({ parser = { delimiter = "," } })
    local delimiter = p._create_delimiter_policy(opts, 0)

    it("line without empty fields", function()
      assert.are.same({ "abc", "de", "f", "g", "h" }, p._parse_line("abc,de,f,g,h", delimiter, quote_char_byte))
    end)

    it("should works for line includes empty fields", function()
      assert.are.same({ "abc", "de", "", "g", "h" }, p._parse_line("abc,de,,g,h", delimiter, quote_char_byte))
      assert.are.same({ "abc", "de", "f", "g", "" }, p._parse_line("abc,de,f,g,", delimiter, quote_char_byte))
      assert.are.same({ "", "abc", "de", "f", "g" }, p._parse_line(",abc,de,f,g", delimiter, quote_char_byte))
      assert.are.same({ "abc", "f", "g", "", "" }, p._parse_line("abc,f,g,,", delimiter, quote_char_byte))
    end)

    it("empty line", function()
      assert.are.same({}, p._parse_line("", delimiter, quote_char_byte))
    end)
    it("should works for line includes quoted comma.", function()
      assert.are.same({ "abc", "de", '"f,g"', "h" }, p._parse_line('abc,de,"f,g",h', delimiter, quote_char_byte))
    end)
    it("handles fields with missing closing quotes", function()
      assert.are.same({ "abc", "de", '"f,g,h' }, p._parse_line('abc,de,"f,g,h', delimiter, quote_char_byte))
    end)
    it("should work for line including single quoted comma.", function()
      local single_quote_char = "'"
      local single_quote_char_byte = string.byte(single_quote_char)
      assert.are.same({ "abc", "de", "'f,g'", "h" }, p._parse_line("abc,de,'f,g',h", delimiter, single_quote_char_byte))
    end)

    it("parses tab-delimited lines correctly", function()
      local _opts = config.get({ parser = { delimiter = "\t" } })
      local _delimiter = p._create_delimiter_policy(_opts, 0)
      assert.are.same({ "abc", "de", "f", "g", "h" }, p._parse_line("abc\tde\tf\tg\th", _delimiter, quote_char_byte))
    end)

    it("parses multi-character delimiter correctly", function()
      local _opts = config.get({ parser = { delimiter = "|!|!|" } })
      local _delimiter = p._create_delimiter_policy(_opts, 0)
      assert.are.same(
        { "abc", "de", "f", "g", "h" },
        p._parse_line("abc|!|!|de|!|!|f|!|!|g|!|!|h", _delimiter, quote_char_byte)
      )
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
      local opts = config.get({ parser = { async_chunksize = 1, delimiter = "," } })
      p.iter_lines_async(buf, nil, nil, {
        on_line = function(_, _, line)
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
        on_line = function(_, _, line)
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
