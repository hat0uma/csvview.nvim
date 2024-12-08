---@class CsvView.Tests.EnableCase
---@field name string
---@field opts CsvViewOptions
---@field lines string[]
---@field expected string[]

---@type CsvView.Tests.EnableCase[]
return {
  {
    name = "display_mode  = 'highlight'",
    opts = {
      view = {
        display_mode = "highlight",
        spacing = 1,
        min_column_width = 5,
      },
      parser = {
        comments = { "#", "--" },
      },
    },
    lines = {
      "# this is comment, so it should be ignored",
      "-- this is also comment, so it should be ignored",
      "column1(number),column2(emoji),column3(string)",
      "111,😀,abcde",
      "222222222222,😒😒😒😒,fgh",
      "333333333333333333,😎b😎b😎b😎b😎b😎b,ijk",
    },
    expected = {
      "# this is comment, so it should be ignored",
      "-- this is also comment, so it should be ignored",
      "column1(number)    ,column2(emoji)     ,column3(string) ",
      "                111,😀                 ,abcde           ",
      "       222222222222,😒😒😒😒           ,fgh             ",
      " 333333333333333333,😎b😎b😎b😎b😎b😎b ,ijk             ",
    },
  },
  {
    name = "display_mode  = 'border'",
    opts = {
      view = {
        display_mode = "border",
        spacing = 1,
        min_column_width = 5,
      },
      parser = {
        comments = { "#", "--" },
      },
    },
    lines = {
      "# this is comment, so it should be ignored",
      "-- this is also comment, so it should be ignored",
      "column1(number),column2(emoji),column3(string)",
      "111,😀,abcde",
      "222222222222,😒😒😒😒,fgh",
      "333333333333333333,😎b😎b😎b😎b😎b😎b,ijk",
    },
    expected = {
      "# this is comment, so it should be ignored",
      "-- this is also comment, so it should be ignored",
      "column1(number)    │column2(emoji)     │column3(string) ",
      "                111│😀                 │abcde           ",
      "       222222222222│😒😒😒😒           │fgh             ",
      " 333333333333333333│😎b😎b😎b😎b😎b😎b │ijk             ",
    },
  },
}
