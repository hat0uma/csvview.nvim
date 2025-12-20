local sniffer = require("csvview.sniffer")
local testutil = require("tests.testutil")
local util = require("csvview.util")

describe("csvview.sniffer", function()
  local opts = {
    max_lookahead = 50,
  }

  local is_comment = util.create_is_comment({ parser = { comments = { "#" } } })

  describe("detect_delimiter", function()
    it("should detect comma delimiter", function()
      local lines = {
        "name,age,city",
        "John,25,New York",
        "Jane,30,Los Angeles",
      }

      local delimiter = sniffer.detect_delimiter(lines, { ",", "\t", ";", "|" }, '"', is_comment, opts.max_lookahead)
      assert.equals(",", delimiter)
    end)

    it("should detect tab delimiter", function()
      local lines = {
        "name\tage\tcity",
        "John\t25\tNew York",
        "Jane\t30\tLos Angeles",
      }

      local delimiter = sniffer.detect_delimiter(lines, { ",", "\t", ";", "|" }, '"', is_comment, opts.max_lookahead)
      assert.equals("\t", delimiter)
    end)

    it("should detect semicolon delimiter", function()
      local lines = {
        "name;age;city",
        "John;25;New York",
        "Jane;30;Los Angeles",
      }

      local delimiter = sniffer.detect_delimiter(lines, { ",", "\t", ";", "|" }, '"', is_comment, opts.max_lookahead)
      assert.equals(";", delimiter)
    end)

    it("should detect pipe delimiter", function()
      local lines = {
        "name|age|city",
        "John|25|New York",
        "Jane|30|Los Angeles",
      }

      local delimiter = sniffer.detect_delimiter(lines, { ",", "\t", ";", "|" }, '"', is_comment, opts.max_lookahead)
      assert.equals("|", delimiter)
    end)

    it("should handle quoted fields with embedded delimiters", function()
      local lines = {
        'name,age,"city,state"',
        'John,25,"New York, NY"',
        'Jane,30,"Los Angeles, CA"',
      }

      local delimiter = sniffer.detect_delimiter(lines, { ",", "\t", ";", "|" }, '"', is_comment, opts.max_lookahead)
      assert.equals(",", delimiter)
    end)

    it("should prefer delimiter with highest consistency", function()
      local lines = {
        "name,age;city",
        "John,25;New York",
        "Jane,30;Los Angeles",
        "Bob,35;Chicago",
      }

      local delimiter = sniffer.detect_delimiter(lines, { ",", "\t", ";", "|" }, '"', is_comment, opts.max_lookahead)
      -- Should prefer comma over semicolon due to better consistency
      assert.equals(",", delimiter)
    end)

    it("should use custom delimiter list", function()
      local lines = {
        "name:age:city",
        "John:25:New York",
        "Jane:30:Los Angeles",
      }

      local delimiter = sniffer.detect_delimiter(lines, { ",", ":" }, '"', is_comment, opts.max_lookahead)
      assert.equals(":", delimiter)
    end)

    it("should return default delimiter for empty buffer", function()
      local delimiter = sniffer.detect_delimiter({}, { ",", "\t", ";", "|" }, '"', is_comment, opts.max_lookahead)
      assert.equals(",", delimiter)
    end)

    it("should return default delimiter for single line", function()
      local delimiter = sniffer.detect_delimiter(
        { "single line" },
        { ",", "\t", ";", "|" },
        '"',
        is_comment,
        opts.max_lookahead
      )
      assert.equals(",", delimiter)
    end)
  end)

  describe("detect_quote_char", function()
    it("should detect double quote character", function()
      local lines = {
        '"name","age","city"',
        '"John","25","New York"',
        '"Jane","30","Los Angeles"',
      }

      local quote_char = sniffer.detect_quote_char(lines, { '"', "'" })
      assert.equals('"', quote_char)
    end)

    it("should detect single quote character", function()
      local lines = {
        "'name','age','city'",
        "'John','25','New York'",
        "'Jane','30','Los Angeles'",
      }

      local quote_char = sniffer.detect_quote_char(lines, { '"', "'" })
      assert.equals("'", quote_char)
    end)

    it("should handle escaped quotes", function()
      local lines = {
        '"name","message"',
        '"John","He said ""Hello"""',
        '"Jane","She replied ""Hi"""',
      }

      local quote_char = sniffer.detect_quote_char(lines, { '"', "'" })
      assert.equals('"', quote_char)
    end)

    it("should return default quote char for no quotes", function()
      local lines = {
        "name,age,city",
        "John,25,New York",
        "Jane,30,Los Angeles",
      }

      local quote_char = sniffer.detect_quote_char(lines, { '"', "'" })
      assert.equals('"', quote_char)
    end)
  end)

  describe("detect_header", function()
    it("should detect header with numeric data", function()
      local lines = {
        "name,age,salary",
        "John,25,50000",
        "Jane,30,60000",
        "Bob,35,70000",
      }

      local header_lnum = sniffer.detect_header(lines, ",", '"', is_comment, opts.max_lookahead)
      assert.equals(1, header_lnum)
    end)

    it("should detect header with comment_lines option", function()
      local lines = {
        "File: data.csv",
        "Created: 2024-01-01",
        "name,age,salary",
        "John,25,50000",
        "Jane,30,60000",
      }

      local is_comment_with_lines = util.create_is_comment({
        parser = {
          comments = {},
          comment_lines = 2,
        },
      })

      local header_lnum = sniffer.detect_header(lines, ",", '"', is_comment_with_lines, opts.max_lookahead)
      assert.equals(3, header_lnum)
    end)

    it("should detect header with combined comment_lines and comment prefix", function()
      local lines = {
        "Metadata line 1",
        "Metadata line 2",
        "# Additional comment",
        "name,age,salary",
        "John,25,50000",
        "Jane,30,60000",
      }

      local is_comment_combined = util.create_is_comment({
        parser = {
          comments = { "#" },
          comment_lines = 2,
        },
      })

      local header_lnum = sniffer.detect_header(lines, ",", '"', is_comment_combined, opts.max_lookahead)
      assert.equals(4, header_lnum)
    end)

    it("should not detect header when first row is numeric", function()
      local lines = {
        "1,25,50000",
        "2,30,60000",
        "3,35,70000",
      }

      local header_lnum = sniffer.detect_header(lines, ",", '"', is_comment, opts.max_lookahead)
      assert.is_nil(header_lnum)
    end)

    it("should handle mixed data types", function()
      local lines = {
        "id,name,active",
        "1,John,true",
        "2,Jane,false",
        "3,Bob,true",
      }

      local header_lnum = sniffer.detect_header(lines, ",", '"', is_comment, opts.max_lookahead)
      assert.equals(1, header_lnum)
    end)

    it("should detect header with comments", function()
      local lines = {
        "# This is a comment",
        "id,name,active",
        "1,John,true",
        "2,Jane,false",
        "3,Bob,true",
      }

      local header_lnum = sniffer.detect_header(lines, ",", '"', is_comment, opts.max_lookahead)
      assert.equals(2, header_lnum)
    end)

    it("should detect header with date columns", function()
      local lines = {
        "name,birth_date,join_time",
        "John,1990-01-15,09:30:00",
        "Jane,1985-12-22,14:15:30",
        "Bob,1992-06-08,11:45:00",
      }

      local header_lnum = sniffer.detect_header(lines, ",", '"', is_comment, opts.max_lookahead)
      assert.equals(1, header_lnum)
    end)

    it("should not detect header when all text rows are similar", function()
      local lines = {
        "electronics,active,high",
        "books,inactive,low",
        "clothing,active,medium",
        "furniture,pending,low",
        "shoes,sold,medium",
      }

      local header_lnum = sniffer.detect_header(lines, ",", '"', is_comment, opts.max_lookahead)
      assert.is_nil(header_lnum)
    end)

    it("should handle boolean values", function()
      local lines = {
        "name,active,verified",
        "John,true,yes",
        "Jane,false,no",
        "Bob,1,y",
      }

      local header_lnum = sniffer.detect_header(lines, ",", '"', is_comment, opts.max_lookahead)
      assert.equals(1, header_lnum)
    end)

    it("should work with float numbers", function()
      local lines = {
        "product,price,tax_rate",
        "Widget,19.99,0.08",
        "Gadget,29.50,0.075",
        "Tool,45.00,0.09",
      }

      local header_lnum = sniffer.detect_header(lines, ",", '"', is_comment, opts.max_lookahead)
      assert.equals(1, header_lnum)
    end)

    it("should return nil for single line", function()
      local header_lnum = sniffer.detect_header({ "name,age,city" }, ",", '"', is_comment, opts.max_lookahead)
      assert.is_nil(header_lnum)
    end)

    it("should return nil for empty buffer", function()
      local header_lnum = sniffer.detect_header({}, ",", '"', is_comment, opts.max_lookahead)
      assert.is_nil(header_lnum)
    end)

    it("should handle inconsistent column counts gracefully", function()
      local lines = {
        "name,age,city",
        "John,25,New York,extra",
        "Jane,30",
        "Bob,35,Chicago",
        "Alice,28,Boston",
      }

      local header_lnum = sniffer.detect_header(lines, ",", '"', is_comment, opts.max_lookahead)
      assert.equals(1, header_lnum)
    end)

    it("should detect header with many columns", function()
      local lines = {
        "col1,col2,col3,col4,col5,col6,col7",
        "1,2,3,4,5,6,7",
        "8,9,10,11,12,13,14",
        "15,16,17,18,19,20,21",
      }

      local header_lnum = sniffer.detect_header(lines, ",", '"', is_comment, opts.max_lookahead)
      assert.equals(1, header_lnum)
    end)

    it("should handle quoted headers", function()
      local lines = {
        '"Product Name","Unit Price","In Stock"',
        '"Widget A",19.99,true',
        '"Widget B",29.99,false',
        '"Widget C",39.99,true',
      }

      local header_lnum = sniffer.detect_header(lines, ",", '"', is_comment, opts.max_lookahead)
      assert.equals(1, header_lnum)
    end)
  end)

  describe("integrated detection", function()
    it("should detect all dialect components", function()
      local lines = {
        '"name","age","city"',
        '"John",25,"New York"',
        '"Jane",30,"Los Angeles"',
        '"Bob",35,"Chicago"',
      }

      local quote_char = sniffer.detect_quote_char(lines, { '"', "'" })
      local delimiter =
        sniffer.detect_delimiter(lines, { ",", "\t", ";", "|" }, quote_char, is_comment, opts.max_lookahead)
      local header_lnum = sniffer.detect_header(lines, delimiter, quote_char, is_comment, opts.max_lookahead)

      assert.equals(",", delimiter)
      assert.equals('"', quote_char)
      assert.equals(1, header_lnum)
    end)

    it("should work with TSV files", function()
      local lines = {
        "name\tage\tcity",
        "John\t25\tNew York",
        "Jane\t30\tLos Angeles",
        "Bob\t35\tChicago",
      }

      local quote_char = sniffer.detect_quote_char(lines, { '"', "'" })
      local delimiter =
        sniffer.detect_delimiter(lines, { ",", "\t", ";", "|" }, quote_char, is_comment, opts.max_lookahead)
      local header_lnum = sniffer.detect_header(lines, delimiter, quote_char, is_comment, opts.max_lookahead)

      assert.equals("\t", delimiter)
      assert.equals('"', quote_char)
      assert.equals(1, header_lnum)
    end)

    it("should handle complex CSV with various features", function()
      local lines = {
        'name,age,"address,with,commas",score',
        'John,25,"123 Main St, New York, NY",85.5',
        'Jane,30,"456 Oak Ave, Los Angeles, CA",92.3',
        'Bob,35,"789 Pine Rd, Chicago, IL",78.9',
      }

      local quote_char = sniffer.detect_quote_char(lines, { '"', "'" })
      local delimiter =
        sniffer.detect_delimiter(lines, { ",", "\t", ";", "|" }, quote_char, is_comment, opts.max_lookahead)
      local header_lnum = sniffer.detect_header(lines, delimiter, quote_char, is_comment, opts.max_lookahead)

      assert.equals(",", delimiter)
      assert.equals('"', quote_char)
      assert.equals(1, header_lnum)
    end)
  end)

  describe("real file examples", function()
    it("should work with test.csv fixture", function()
      local lines = testutil.readlines("tests/fixtures/test.csv")

      local quote_char = sniffer.detect_quote_char(lines, { '"', "'" })
      local delimiter =
        sniffer.detect_delimiter(lines, { ",", "\t", ";", "|" }, quote_char, is_comment, opts.max_lookahead)
      local header_lnum = sniffer.detect_header(lines, delimiter, quote_char, is_comment, opts.max_lookahead)

      assert.equals(",", delimiter)
      assert.equals('"', quote_char)
      assert.equals(1, header_lnum)
    end)

    it("should work with test.tsv fixture", function()
      local lines = testutil.readlines("tests/fixtures/test.tsv")

      local quote_char = sniffer.detect_quote_char(lines, { '"', "'" })
      local delimiter =
        sniffer.detect_delimiter(lines, { ",", "\t", ";", "|" }, quote_char, is_comment, opts.max_lookahead)
      local header_lnum = sniffer.detect_header(lines, delimiter, quote_char, is_comment, opts.max_lookahead)

      assert.equals("\t", delimiter)
      assert.equals('"', quote_char)
      assert.equals(1, header_lnum)
    end)

    it("should work with minimal.csv fixture", function()
      local lines = testutil.readlines("tests/fixtures/minimal.csv")

      local quote_char = sniffer.detect_quote_char(lines, { '"', "'" })
      local delimiter =
        sniffer.detect_delimiter(lines, { ",", "\t", ";", "|" }, quote_char, is_comment, opts.max_lookahead)
      local header_lnum = sniffer.detect_header(lines, delimiter, quote_char, is_comment, opts.max_lookahead)

      assert.equals(",", delimiter)
      assert.equals('"', quote_char)
      assert.equals(1, header_lnum)
    end)
  end)
end)
