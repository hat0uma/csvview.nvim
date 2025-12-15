local strings = require("csvview.strings")

describe("strings", function()
  describe("display_width", function()
    local orig = {}
    local function save_options()
      orig.cellwidth = vim.fn.getcellwidths()
      vim.fn.setcellwidths({})
      orig.fillchars = vim.o.fillchars
      vim.o.fillchars = "vert:|,fold:-,eob:~,lastline:@"
      orig.tabstop = vim.o.tabstop
      vim.o.tabstop = 8
      orig.ambiwidth = vim.o.ambiwidth
    end

    local function restore_options()
      vim.o.ambiwidth = orig.ambiwidth
      vim.fn.setcellwidths(orig.cellwidth)
      vim.o.fillchars = orig.fillchars
      vim.o.tabstop = orig.tabstop
    end

    -- Basic cases (ambiwidth independent)
    local basic_cases = {
      { str = "abc", expected = 3, desc = "ascii" },
      { str = "あいう", expected = 6, desc = "fullwidth japanese" },
      { str = "abc,def,ghi", offset = 0, endpos = 3, expected = 3, desc = "first field" },
      { str = "abc,def,ghi", offset = 4, endpos = 7, expected = 3, desc = "middle field" },
      { str = "a,あ,b", offset = 2, endpos = 5, expected = 2, desc = "japanese in middle" },
    }

    for _, case in ipairs(basic_cases) do
      it(case.desc, function()
        local offset = case.offset or 0
        local endpos = case.endpos or #case.str
        assert.are.same(case.expected, strings.display_width(case.str, offset, endpos))
      end)
    end

    -- Tab cases (tabstop=8)
    describe("with tabs", function()
      save_options()
      vim.o.tabstop = 8

      local tab_cases = {
        -- tab at position 0 expands to 8
        { str = "\tabc", expected = 11, desc = "tab at start" },
        -- "abc" is 3 chars, tab expands to fill to next 8 (8-3=5)
        { str = "abc\tde", expected = 10, desc = "tab after 3 chars" },
        -- only tab after 3 chars
        { str = "abc\tde", offset = 3, endpos = 4, expected = 5, desc = "only tab after 3 chars" },
      }

      for _, case in ipairs(tab_cases) do
        it(case.desc, function()
          local offset = case.offset or 0
          local endpos = case.endpos or #case.str
          assert.are.same(case.expected, strings.display_width(case.str, offset, endpos))
        end)
      end

      restore_options()
    end)

    -- East Asian Ambiguous width cases
    describe("with ambiwidth", function()
      save_options()

      -- Characters like "├─┤" are East Asian Ambiguous
      local ambi_cases = {
        { str = "├─┤", ambiwidth = "single", expected = 3, desc = "box drawing single" },
        { str = "├─┤", ambiwidth = "double", expected = 6, desc = "box drawing double" },
        { str = "①②③", ambiwidth = "single", expected = 3, desc = "circled numbers single" },
        { str = "①②③", ambiwidth = "double", expected = 6, desc = "circled numbers double" },
      }

      for _, case in ipairs(ambi_cases) do
        it(case.desc, function()
          vim.o.ambiwidth = case.ambiwidth
          local offset = case.offset or 0
          local endpos = case.endpos or #case.str
          assert.are.same(case.expected, strings.display_width(case.str, offset, endpos))
        end)
      end

      restore_options()
    end)
  end)

  describe("is_number", function()
    local cases = {
      -- Valid numbers
      { line = "123", expected = true, desc = "integer" },
      { line = "0", expected = true, desc = "zero" },
      { line = "-123", expected = true, desc = "negative integer" },
      { line = "+123", expected = true, desc = "positive integer with sign" },
      { line = "123.456", expected = true, desc = "decimal" },
      { line = "-123.456", expected = true, desc = "negative decimal" },
      { line = ".5", expected = true, desc = "decimal starting with dot" },
      { line = "1e10", expected = true, desc = "scientific notation" },
      { line = "1E10", expected = true, desc = "scientific notation uppercase" },
      { line = "1e-10", expected = true, desc = "scientific notation with minus" },
      { line = "1,234,567", expected = true, desc = "comma separated integer" },

      -- Invalid numbers
      { line = "", expected = false, desc = "empty string" },
      { line = "abc", expected = false, desc = "letters" },
      { line = "123abc", expected = false, desc = "number with trailing letters" },
      { line = "12.34.56", expected = false, desc = "multiple dots" },
      { line = "-", expected = false, desc = "only sign" },
    }

    for _, case in ipairs(cases) do
      it(string.format("%s %s: %s ", case.desc, case.expected and "is number" or "is not number", case.line), function()
        assert.are.same(case.expected, strings.is_number(case.line, 0, #case.line))
      end)
    end

    describe("with offset and endpos", function()
      it("extracts number from middle of line", function()
        local line = "abc,123,def"
        assert.are.same(true, strings.is_number(line, 4, 7))
      end)

      it("extracts non-number from middle of line", function()
        local line = "abc,def,123"
        assert.are.same(false, strings.is_number(line, 4, 7))
      end)
    end)
  end)
end)
