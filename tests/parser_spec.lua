---@diagnostic disable: await-in-sync

local CsvViewParser = require("csvview.parser")
local config = require("csvview.config")

--- test cases for the CSV parser
---@type {
---  it: string,
---  opts?: CsvView.Options,
---  lines: string[],
---  startlnum: integer?,
---  endlnum: integer?,
---  max_lookahead?: integer,
---  expected: {
---    is_comment: boolean?,
---    fields: CsvView.Parser.FieldInfo[],
---  }[],
--- }[]
local cases = {
  {
    it = "should parse line without empty fields",
    lines = { "abc,de,f,g,h" },
    expected = {
      {
        is_comment = false,
        fields = {
          { start_pos = 1, text = "abc" },
          { start_pos = 5, text = "de" },
          { start_pos = 8, text = "f" },
          { start_pos = 10, text = "g" },
          { start_pos = 12, text = "h" },
        },
      },
    },
  },
  {
    it = "should parse line with empty fields",
    lines = {
      "abc,de,,g,h",
      "abc,de,f,g,",
      ",abc,de,f,g",
      "abc,f,g,,",
    },
    expected = {
      {
        is_comment = false,
        fields = {
          { start_pos = 1, text = "abc" },
          { start_pos = 5, text = "de" },
          { start_pos = 8, text = "" },
          { start_pos = 9, text = "g" },
          { start_pos = 11, text = "h" },
        },
      },
      {
        is_comment = false,
        fields = {
          { start_pos = 1, text = "abc" },
          { start_pos = 5, text = "de" },
          { start_pos = 8, text = "f" },
          { start_pos = 10, text = "g" },
          { start_pos = 12, text = "" },
        },
      },
      {
        is_comment = false,
        fields = {
          { start_pos = 1, text = "" },
          { start_pos = 2, text = "abc" },
          { start_pos = 6, text = "de" },
          { start_pos = 9, text = "f" },
          { start_pos = 11, text = "g" },
        },
      },
      {
        is_comment = false,
        fields = {
          { start_pos = 1, text = "abc" },
          { start_pos = 5, text = "f" },
          { start_pos = 7, text = "g" },
          { start_pos = 9, text = "" },
          { start_pos = 10, text = "" },
        },
      },
    },
  },
  {
    it = "should parse empty line",
    lines = { "" },
    expected = {
      {
        is_comment = false,
        fields = {},
      },
    },
  },
  {
    it = "should parse line with quoted comma",
    lines = { 'abc,de,"f,g",h' },
    expected = {
      {
        is_comment = false,
        fields = {
          { start_pos = 1, text = "abc" },
          { start_pos = 5, text = "de" },
          { start_pos = 8, text = '"f,g"' },
          { start_pos = 14, text = "h" },
        },
      },
    },
  },
  {
    it = "should parse line with missing closing quotes",
    lines = { 'abc,de,"f,g,h' },
    expected = {
      {
        is_comment = false,
        fields = {
          { start_pos = 1, text = "abc" },
          { start_pos = 5, text = "de" },
          { start_pos = 8, text = '"f,g,h' },
        },
      },
    },
  },
  {
    it = "should parse line with single quoted comma",
    opts = { parser = { quote_char = "'" } },
    lines = { "abc,de,'f,g',h" },
    expected = {
      {
        is_comment = false,
        fields = {
          { start_pos = 1, text = "abc" },
          { start_pos = 5, text = "de" },
          { start_pos = 8, text = "'f,g'" },
          { start_pos = 14, text = "h" },
        },
      },
    },
  },
  {
    it = "should parse tab-delimited line",
    opts = { parser = { delimiter = "\t" } },
    lines = { "abc\tde\tf\tg\th" },
    expected = {
      {
        is_comment = false,
        fields = {
          { start_pos = 1, text = "abc" },
          { start_pos = 5, text = "de" },
          { start_pos = 8, text = "f" },
          { start_pos = 10, text = "g" },
          { start_pos = 12, text = "h" },
        },
      },
    },
  },
  {
    it = "should parse line with multi-character delimiter",
    opts = { parser = { delimiter = "|!|!|" } },
    lines = { "abc|!|!|de|!|!|f|!|!|g|!|!|h" },
    expected = {
      {
        is_comment = false,
        fields = {
          { start_pos = 1, text = "abc" },
          { start_pos = 9, text = "de" },
          { start_pos = 16, text = "f" },
          { start_pos = 22, text = "g" },
          { start_pos = 28, text = "h" },
        },
      },
    },
  },
  {
    it = "should parse only the specified range",
    startlnum = 2,
    endlnum = 3,
    lines = {
      "a,b,c,d,e,,",
      "f,g,h,i,j,k,l",
      "",
      "m,n",
    },
    expected = {
      {
        is_comment = false,
        fields = {
          { start_pos = 1, text = "f" },
          { start_pos = 3, text = "g" },
          { start_pos = 5, text = "h" },
          { start_pos = 7, text = "i" },
          { start_pos = 9, text = "j" },
          { start_pos = 11, text = "k" },
          { start_pos = 13, text = "l" },
        },
      },
      {
        is_comment = false,
        fields = {},
      },
    },
  },
  {
    it = "should ignore comment lines",
    opts = { parser = { async_chunksize = 4, comments = { "#" } } },
    lines = {
      "a,b,c,d,e,,",
      "# this is a comment",
      "f,g,h,i,j,k,l",
      "",
      "m,n",
    },
    expected = {
      {
        is_comment = false,
        fields = {
          { start_pos = 1, text = "a" },
          { start_pos = 3, text = "b" },
          { start_pos = 5, text = "c" },
          { start_pos = 7, text = "d" },
          { start_pos = 9, text = "e" },
          { start_pos = 11, text = "" },
          { start_pos = 12, text = "" },
        },
      },
      {
        is_comment = true,
        fields = {},
      },
      {
        is_comment = false,
        fields = {
          { start_pos = 1, text = "f" },
          { start_pos = 3, text = "g" },
          { start_pos = 5, text = "h" },
          { start_pos = 7, text = "i" },
          { start_pos = 9, text = "j" },
          { start_pos = 11, text = "k" },
          { start_pos = 13, text = "l" },
        },
      },
      {
        is_comment = false,
        fields = {},
      },
      {
        is_comment = false,
        fields = {
          { start_pos = 1, text = "m" },
          { start_pos = 3, text = "n" },
        },
      },
    },
  },
  {
    it = "should parse multi-line quoted fields",
    lines = {
      '"123","This is a',
      "multiline comment",
      'spanning several lines.",ok',
    },
    max_lookahead = 20,
    expected = {
      {
        is_comment = false,
        fields = {
          { start_pos = 1, text = '"123"' },
          { start_pos = 7, text = { '"This is a', "multiline comment", 'spanning several lines."' } },
          { start_pos = 26, text = "ok" },
        },
      },
    },
  },
  {
    it = "should parse multi-line quoted fields with empty lines",
    lines = {
      '"header1","header2"',
      '"value1","multi',
      "",
      'line value2"',
    },
    max_lookahead = 20,
    expected = {
      {
        is_comment = false,
        fields = {
          { start_pos = 1, text = '"header1"' },
          { start_pos = 11, text = '"header2"' },
        },
      },
      {
        is_comment = false,
        fields = {
          { start_pos = 1, text = '"value1"' },
          { start_pos = 10, text = { '"multi', "", 'line value2"' } },
        },
      },
    },
  },
  {
    it = "should parse quoted fields with escaped quotes",
    lines = {
      '"header1","header2"',
      '"value1","multi ""quoted"" value2"',
    },
    max_lookahead = 20,
    expected = {
      {
        is_comment = false,
        fields = {
          { start_pos = 1, text = '"header1"' },
          { start_pos = 11, text = '"header2"' },
        },
      },
      {
        is_comment = false,
        fields = {
          { start_pos = 1, text = '"value1"' },
          { start_pos = 10, text = '"multi ""quoted"" value2"' },
        },
      },
    },
  },
}

describe("CsvViewParser", function()
  config.setup({ parser = { async_chunksize = 1 } })

  for _, case in ipairs(cases) do
    it(case.it, function()
      local opts = config.get(case.opts)
      local bufnr = vim.api.nvim_create_buf(false, true)
      local parser = CsvViewParser:new(bufnr, opts)
      parser._max_lookahead = case.max_lookahead or 0

      vim.api.nvim_buf_set_lines(bufnr, 0, #case.lines, false, case.lines)

      local thread = coroutine.running()
      local results = {} ---@type { is_comment: boolean?, fields: CsvView.Parser.FieldInfo[] }[]
      parser:parse_lines({
        on_end = vim.schedule_wrap(function()
          coroutine.resume(thread)
        end),
        on_line = function(lnum, is_comment, fields)
          table.insert(results, { is_comment = is_comment, fields = fields })
        end,
      }, case.startlnum, case.endlnum)

      coroutine.yield()
      vim.api.nvim_buf_delete(bufnr, { force = true })
      assert.are.same(#case.expected, #results)
      for i = 1, #results do
        assert.are.same(case.expected[i].is_comment, results[i].is_comment)
        assert.are.same(case.expected[i].fields, results[i].fields)
      end
    end)
  end
end)
