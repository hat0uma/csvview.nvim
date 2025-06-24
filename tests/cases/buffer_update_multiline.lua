--- Test cases for csvview when updating multi-line fields.
---@type { describe:string, cases: CsvView.Tests.UpdateCase[] }[]
return {
  {
    describe = "and updating multi-line fields",
    cases = {
      {
        name = "renders correctly when a line is added within a multi-line field",
        lines = {
          "ID,Name,Address",
          '1,"John Doe","123 Main St',
          'New York, NY 10001"',
        },
        changes = {
          {
            type = "insert",
            line = 3,
            after = "Apt 4B",
          },
        },
        expected = {
          "ID     ,Name        ,Address              ",
          '      1,"John Doe"  ,"123 Main St         ',
          "                     Apt 4B               ",
          '                     New York, NY 10001"  ',
        },
      },
      {
        name = "renders correctly when a line is removed from a multi-line field",
        lines = {
          "ID,Name,Address",
          '1,"John Doe","123 Main St',
          "Apt 4B",
          'New York, NY 10001"',
        },
        changes = {
          {
            type = "delete",
            line = 3,
          },
        },
        expected = {
          "ID     ,Name        ,Address              ",
          '      1,"John Doe"  ,"123 Main St         ',
          '                     New York, NY 10001"  ',
        },
      },
      {
        name = "renders correctly when a multi-line field is merged into a single line",
        lines = {
          "ID,Name,Address",
          '1,"John Doe","123 Main St',
          'New York, NY 10001"',
        },
        changes = {
          {
            type = "modify",
            line = 2,
            after = '1,"John Doe","123 Main St New York, NY 10001"',
          },
          {
            type = "delete",
            line = 3,
          },
        },
        expected = {
          "ID     ,Name        ,Address                           ",
          '      1,"John Doe"  ,"123 Main St New York, NY 10001"  ',
        },
      },
      {
        name = "renders correctly when a single-line field is split into a multi-line field",
        lines = {
          "ID,Name,Address",
          '1,"John Doe","123 Main St, New York, NY 10001"',
        },
        changes = {
          {
            type = "modify",
            line = 2,
            after = '1,"John Doe","123 Main St,',
          },
          {
            type = "insert",
            line = 3,
            after = 'New York, NY 10001"',
          },
        },
        expected = {
          "ID     ,Name        ,Address              ",
          '      1,"John Doe"  ,"123 Main St,        ',
          '                     New York, NY 10001"  ',
        },
      },
      {
        name = "renders correctly when the opening quote of a multi-line field is removed (structure breaking)",
        lines = {
          "ID,Name,Address",
          '1,"John Doe","123 Main St',
          'New York, NY 10001"',
        },
        changes = {
          {
            type = "modify",
            line = 2,
            after = "1,John Doe,123 Main St",
          },
        },
        expected = {
          "ID        ,Name        ,Address      ",
          "         1,John Doe    ,123 Main St  ",
          'New York  , NY 10001"  ',
        },
      },
      {
        name = "renders correctly when the closing quote of a multi-line field is removed (unterminated field)",
        lines = {
          "ID,Name,Address",
          '1,"John Doe","123 Main St',
          'New York, NY 10001"',
          '2,"Jane Smith","456 Oak Ave"',
        },
        changes = {
          {
            type = "modify",
            line = 3,
            after = "New York, NY 10001",
          },
        },
        expected = {
          "ID     ,Name        ,Address                       ",
          '      1,"John Doe"  ,"123 Main St                  ',
          "                     New York, NY 10001            ",
          '                     2,"Jane Smith","456 Oak Ave"  ',
        },
      },
      {
        name = "renders correctly when adding a closing quote in the middle of a multi-line field",
        lines = {
          "ID,Name,Address",
          '1,"John Doe","123 Main St',
          "Apt 4B",
          'New York, NY 10001"',
        },
        changes = {
          {
            type = "modify",
            line = 2,
            after = '1,"John Doe","123 Main St"',
          },
        },
        expected = {
          "ID        ,Name        ,Address        ",
          '         1,"John Doe"  ,"123 Main St"  ',
          "Apt 4B    ",
          'New York  , NY 10001"  ',
        },
      },
      {
        name = "renders correctly when a multi-line max_lookahead is exceeded",
        lines = {
          "ID,Name,Address",
          '1,"L01',
          "L02",
          "L03",
          "L04",
          "L05",
          "L06",
          "L07",
          "L08",
          "L09",
          "L10",
          "L11",
          '2,"Jane Smith","456 Oak Ave"',
        },
        changes = {},
        expected = {
          "ID     ,Name          ,Address        ",
          '      1,"L01          ',
          "        L02           ",
          "        L03           ",
          "        L04           ",
          "        L05           ",
          "        L06           ",
          "        L07           ",
          "        L08           ",
          "        L09           ",
          "        L10           ",
          "        L11           ",
          '      2,"Jane Smith"  ,"456 Oak Ave"',
        },
      },
    },
  },
}
