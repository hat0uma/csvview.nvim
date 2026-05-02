---@class CsvView.Tests.EnableCase
---@field name string
---@field opts CsvView.Options
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
  {
    name = "display_mode  = 'highlight' with left and right spacing",
    opts = {
      view = {
        display_mode = "highlight",
        spacing = { left = 1, right = 1 },
        min_column_width = 5,
      },
    },
    lines = {
      "id,alpha2,alpha3,name",
      "4,af,afg,Afghanistan",
      "8,al,alb,Albania",
      "12,dz,dza,Algeria",
    },
    expected = {
      "id    , alpha2 , alpha3 , name        ",
      "    4 , af     , afg    , Afghanistan ",
      "    8 , al     , alb    , Albania     ",
      "   12 , dz     , dza    , Algeria     ",
    },
  },
  {
    name = "display_mode  = 'border' with left and right spacing",
    opts = {
      view = {
        display_mode = "border",
        spacing = { left = 1, right = 1 },
        min_column_width = 5,
      },
    },
    lines = {
      "id,alpha2,alpha3,name",
      "4,af,afg,Afghanistan",
      "8,al,alb,Albania",
      "12,dz,dza,Algeria",
    },
    expected = {
      "id    │ alpha2 │ alpha3 │ name        ",
      "    4 │ af     │ afg    │ Afghanistan ",
      "    8 │ al     │ alb    │ Albania     ",
      "   12 │ dz     │ dza    │ Algeria     ",
    },
  },
  {
    name = "multi-byte delimiter and multi-characters delimiter",
    opts = {
      view = {
        display_mode = "highlight",
        spacing = 1,
        min_column_width = 5,
      },
      parser = {
        delimiter = "|🍣|",
        comments = { "#", "--" },
      },
    },
    lines = {
      "# this is comment, so it should be ignored",
      "-- this is also comment, so it should be ignored",
      "column1(number)|🍣|column2(emoji)|🍣|column3(string)",
      "111|🍣|😀|🍣|abcde",
      "222222222222|🍣|😒😒😒😒|🍣|fgh",
      "333333333333333333|🍣|😎b😎b😎b😎b😎b😎b|🍣|ijk",
    },
    expected = {
      "# this is comment, so it should be ignored",
      "-- this is also comment, so it should be ignored",
      "column1(number)    |🍣|column2(emoji)     |🍣|column3(string) ",
      "                111|🍣|😀                 |🍣|abcde           ",
      "       222222222222|🍣|😒😒😒😒           |🍣|fgh             ",
      " 333333333333333333|🍣|😎b😎b😎b😎b😎b😎b |🍣|ijk             ",
    },
  },
  {
    name = "multi-byte delimiter and multi-characters delimiter with border display",
    opts = {
      view = {
        display_mode = "border",
        spacing = 1,
        min_column_width = 5,
      },
      parser = {
        delimiter = "|🍣|",
        comments = { "#", "--" },
      },
    },
    lines = {
      "# this is comment, so it should be ignored",
      "-- this is also comment, so it should be ignored",
      "column1(number)|🍣|column2(emoji)|🍣|column3(string)",
      "111|🍣|😀|🍣|abcde",
      "222222222222|🍣|😒😒😒😒|🍣|fgh",
      "333333333333333333|🍣|😎b😎b😎b😎b😎b😎b|🍣|ijk",
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
  {
    name = "multiline fields",
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
      '111,😀,"abcde',
      "fgh",
      'ijk"',
    },
    expected = {
      "# this is comment, so it should be ignored",
      "-- this is also comment, so it should be ignored",
      "column1(number) ,column2(emoji) ,column3(string) ",
      '             111,😀             ,"abcde          ',
      "                                 fgh             ",
      '                                 ijk"            ',
    },
  },
  {
    name = "multiline fields multi-byte delimiter and multi-characters delimiter",
    opts = {
      view = {
        display_mode = "highlight",
        spacing = 1,
        min_column_width = 5,
      },
      parser = {
        delimiter = "|🍣|",
        comments = { "#", "--" },
      },
    },
    lines = {
      "# this is comment, so it should be ignored",
      "-- this is also comment, so it should be ignored",
      "column1(number)|🍣|column2(emoji)|🍣|column3(string)",
      '111|🍣|😀|🍣|"abcde',
      "fgh",
      'ijk"',
    },
    expected = {
      "# this is comment, so it should be ignored",
      "-- this is also comment, so it should be ignored",
      "column1(number) |🍣|column2(emoji) |🍣|column3(string) ",
      '             111|🍣|😀             |🍣|"abcde          ',
      "                                       fgh             ",
      '                                       ijk"            ',
    },
  },
  {
    name = "multiline fields multi-byte delimiter and multi-characters delimiter with border display",
    opts = {
      view = {
        display_mode = "border",
        spacing = 1,
        min_column_width = 5,
      },
      parser = {
        delimiter = "|🍣|",
        comments = { "#", "--" },
      },
    },
    lines = {
      "# this is comment, so it should be ignored",
      "-- this is also comment, so it should be ignored",
      "column1(number)|🍣|column2(emoji)|🍣|column3(string)",
      '111|🍣|😀|🍣|"abcde',
      "fgh",
      'ijk"',
    },
    expected = {
      "# this is comment, so it should be ignored",
      "-- this is also comment, so it should be ignored",
      "column1(number) │column2(emoji) │column3(string) ",
      '             111│😀             │"abcde          ',
      "                                 fgh             ",
      '                                 ijk"            ',
    },
  },
  {
    name = "multiline fields with left and right spacing",
    opts = {
      view = {
        display_mode = "border",
        spacing = { left = 1, right = 1 },
        min_column_width = 5,
      },
    },
    lines = {
      "a,b,c",
      '1,2,"x',
      "y",
      'z"',
    },
    expected = {
      "a     │ b     │ c     ",
      '    1 │     2 │ "x    ',
      "                y     ",
      '                z"    ',
    },
  },
}
