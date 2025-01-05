local Cmdline = require("csvview.cmdline")

describe("Cmdline", function()
  local cmdline = Cmdline:new({
    {
      name = "text1",
      set = function(options, value)
        options.section.text1 = value
      end,
    },
    {
      name = "text2",
      set = function(options, value)
        options.section.text2 = value
      end,
    },
    {
      name = "number",
      set = function(options, value)
        options.section.number = tonumber(value)
      end,
    },
    {
      name = "another",
      set = function(options, value)
        options.another = value
      end,
    },
  })

  describe("parse", function()
    local cases = {
      {
        name = "should parse a single option",
        input = "text1=abc",
        default = { section = {} },
        expected = { section = { text1 = "abc" } },
      },
      {
        name = "should parse multiple options",
        input = "text1=abc number=2",
        default = { section = {} },
        expected = { section = { text1 = "abc", number = 2 } },
      },
      {
        name = "should ignore options not in the list",
        input = "text1=abc number=2 unknown_option=3",
        default = { section = {} },
        expected = { section = { text1 = "abc", number = 2 } },
      },
      {
        name = "should parse escaped spaces",
        input = "text1=abc number=2 another=escaped\\ space\\ value",
        default = { section = {} },
        expected = { section = { text1 = "abc", number = 2 }, another = "escaped space value" },
      },
      {
        name = "should parse escaped tabs",
        input = "text1=\\t1\\t",
        default = { section = {} },
        expected = { section = { text1 = "\t1\t" } },
      },
      {
        name = "should use the default value if the option is not specified",
        input = "number=3",
        default = { section = { text1 = "default", number = 1 }, another = "default" },
        expected = { section = { text1 = "default", number = 3 }, another = "default" },
      },
    }

    for _, case in ipairs(cases) do
      it(case.name, function()
        local result = cmdline:parse(case.input, case.default)
        assert.are_same(case.expected, result)
      end)
    end
  end)

  describe("complete", function()
    local cases = {
      {
        name = "should return all options when no input is given",
        assertions = {
          {
            arg_lead = "",
            cmd_line = "",
            expected = { "text1=", "text2=", "number=", "another=" },
          },
        },
      },
      {
        name = "should return options that start with the input",
        assertions = {
          {
            arg_lead = "text",
            cmd_line = "MyCommand text",
            expected = { "text1=", "text2=" },
          },
          {
            arg_lead = "text1",
            cmd_line = "MyCommand text1",
            expected = { "text1=" },
          },
          {
            arg_lead = "a",
            cmd_line = "MyCommand a",
            expected = { "another=" },
          },
        },
      },
      {
        name = "should return options not already in the command line",
        assertions = {
          {
            arg_lead = "",
            cmd_line = "MyCommand text1=abc ",
            expected = { "text2=", "number=", "another=" },
          },
          {
            arg_lead = "a",
            cmd_line = "MyCommand another=abc a",
            expected = {},
          },
        },
      },
    }

    for _, case in ipairs(cases) do
      it(case.name, function()
        for _, assertion in ipairs(case.assertions) do
          local result = cmdline:complete(assertion.arg_lead, assertion.cmd_line, assertion.cmd_line:len())
          assert.are_same(assertion.expected, result)
        end
      end)
    end
  end)
end)
