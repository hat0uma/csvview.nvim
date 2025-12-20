---@diagnostic disable: await-in-sync

local CsvViewParser = require("csvview.parser")
local config = require("csvview.config")
local util = require("csvview.util")

--- test cases for the CSV parser
---@type {
---  it: string,
---  opts?: CsvView.Options,
---  lines: string[],
---  startlnum: integer?,
---  endlnum: integer?,
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
    it = "should parse line with quoted comma2",
    lines = { 'abc,de,"f,g"' },
    expected = {
      {
        is_comment = false,
        fields = {
          { start_pos = 1, text = "abc" },
          { start_pos = 5, text = "de" },
          { start_pos = 8, text = '"f,g"' },
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
    it = "should treat first N lines as comments with comment_lines option",
    opts = { parser = { comment_lines = 2, comments = {} } },
    lines = {
      "File: test.csv",
      "Date: 2024-01-01",
      "name,age,city",
      "John,25,New York",
    },
    expected = {
      {
        is_comment = true,
        fields = {},
      },
      {
        is_comment = true,
        fields = {},
      },
      {
        is_comment = false,
        fields = {
          { start_pos = 1, text = "name" },
          { start_pos = 6, text = "age" },
          { start_pos = 10, text = "city" },
        },
      },
      {
        is_comment = false,
        fields = {
          { start_pos = 1, text = "John" },
          { start_pos = 6, text = "25" },
          { start_pos = 9, text = "New York" },
        },
      },
    },
  },
  {
    it = "should combine comment_lines and comment prefix detection",
    opts = { parser = { comment_lines = 2, comments = { "#" } } },
    lines = {
      "File: test.csv",
      "Date: 2024-01-01",
      "# This is also a comment",
      "name,age,city",
      "John,25,New York",
    },
    expected = {
      {
        is_comment = true,
        fields = {},
      },
      {
        is_comment = true,
        fields = {},
      },
      {
        is_comment = true,
        fields = {},
      },
      {
        is_comment = false,
        fields = {
          { start_pos = 1, text = "name" },
          { start_pos = 6, text = "age" },
          { start_pos = 10, text = "city" },
        },
      },
      {
        is_comment = false,
        fields = {
          { start_pos = 1, text = "John" },
          { start_pos = 6, text = "25" },
          { start_pos = 9, text = "New York" },
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
  {
    it = "should parse multi-line quoted fields with empty lines",
    lines = {
      "header1,header2",
      'value1,"multi',
      "",
    },
    max_lookahead = 20,
    expected = {
      {
        is_comment = false,
        fields = {
          { start_pos = 1, text = "header1" },
          { start_pos = 9, text = "header2" },
        },
      },
      {
        is_comment = false,
        fields = {
          { start_pos = 1, text = "value1" },
          { start_pos = 8, text = { '"multi', "" } },
        },
      },
    },
  },
  {
    it = "should handle multiline fields with embedded empty lines",
    lines = {
      "Name,Bio",
      'John,"Engineer',
      "",
      "at TechCorp",
      "",
      'Working on AI projects"',
    },
    max_lookahead = 20,
    expected = {
      {
        is_comment = false,
        fields = {
          { start_pos = 1, text = "Name" },
          { start_pos = 6, text = "Bio" },
        },
      },
      {
        is_comment = false,
        fields = {
          { start_pos = 1, text = "John" },
          { start_pos = 6, text = { '"Engineer', "", "at TechCorp", "", 'Working on AI projects"' } },
        },
      },
    },
  },
  {
    it = "should parse multiline fields with various quote patterns",
    lines = {
      "Name,Description",
      '"Alice","Multi-line description',
      'with ""embedded quotes""',
      'and regular text"',
      '"Bob","Simple text"',
    },
    max_lookahead = 20,
    expected = {
      {
        is_comment = false,
        fields = {
          { start_pos = 1, text = "Name" },
          { start_pos = 6, text = "Description" },
        },
      },
      {
        is_comment = false,
        fields = {
          { start_pos = 1, text = '"Alice"' },
          { start_pos = 9, text = { '"Multi-line description', 'with ""embedded quotes""', 'and regular text"' } },
        },
      },
      {
        is_comment = false,
        fields = {
          { start_pos = 1, text = '"Bob"' },
          { start_pos = 7, text = '"Simple text"' },
        },
      },
    },
  },
  {
    it = "should handle incomplete multiline fields at end of buffer",
    lines = {
      "Name,Description",
      'John,"This is an incomplete',
      "multiline field without closing quote",
    },
    max_lookahead = 20,
    expected = {
      {
        is_comment = false,
        fields = {
          { start_pos = 1, text = "Name" },
          { start_pos = 6, text = "Description" },
        },
      },
      {
        is_comment = false,
        fields = {
          { start_pos = 1, text = "John" },
          { start_pos = 6, text = { '"This is an incomplete', "multiline field without closing quote" } },
        },
      },
    },
  },
  {
    it = "should handle incomplete multiline fields that reaches max_lookahead",
    lines = {
      "Name,Description",
      'John,"This is an incomplete',
      "multiline field without closing quote",
      "and more text that exceeds the lookahead limit",
      '"',
    },
    opts = { parser = { max_lookahead = 2 } },
    expected = {
      {
        is_comment = false,
        fields = {
          { start_pos = 1, text = "Name" },
          { start_pos = 6, text = "Description" },
        },
      },
      {
        is_comment = false,
        fields = {
          { start_pos = 1, text = "John" },
          {
            start_pos = 6,
            text = {
              '"This is an incomplete',
              "multiline field without closing quote",
              "and more text that exceeds the lookahead limit",
            },
          },
        },
      },
      {
        is_comment = false,
        fields = {
          { start_pos = 1, text = '"' },
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
      local quote_char = util.resolve_quote_char(bufnr, opts)
      local delimiter = util.resolve_delimiter(bufnr, opts, quote_char)
      local parser = CsvViewParser:new(bufnr, opts, quote_char, delimiter)

      vim.api.nvim_buf_set_lines(bufnr, 0, #case.lines, false, case.lines)

      local results = {} ---@type { is_comment: boolean?, fields: CsvView.Parser.FieldInfo[] }[]
      local startlnum = case.startlnum or 1
      local endlnum = case.endlnum or #case.lines
      local lnum = startlnum

      while lnum <= endlnum do
        local is_comment, fields, parse_endlnum = parser:parse_line(lnum)
        table.insert(results, { is_comment = is_comment, fields = fields })
        lnum = parse_endlnum + 1
      end

      vim.api.nvim_buf_delete(bufnr, { force = true })
      assert.are.same(
        #case.expected,
        #results,
        vim.inspect({
          expected = case.expected,
          result = results,
        })
      )
      for i = 1, #results do
        assert.are.same(case.expected[i].is_comment, results[i].is_comment)
        assert.are.same(case.expected[i].fields, results[i].fields)
      end
    end)
  end
end)
