---@class CsvView.Tests.UpdateCase
---@field name string
---@field lines string[]
---@field changes CsvView.Tests.UpdateCase.Change[]
---@field expected string[]

---@class CsvView.Tests.UpdateCase.Change
---@field type "insert" | "delete" | "modify"
---@field line integer
---@field after string?

--- Test cases for csvview when updating the buffer.
---@type { describe:string, cases: CsvView.Tests.UpdateCase[] }
return {
  -----------------------------------------------------------
  -- Line Modify
  -----------------------------------------------------------
  {
    describe = "and modifying a line",
    cases = {
      {
        name = "renders correctly when column width grows",
        lines = {
          "Index,ID,Name,Email,Birthday",
          "1,XUMMW7737Axxxxxxxx,Jane Davis,jane.williams@example.org,1964-03-22",
          "2,CFLFGKJX4M,John Martinez,emily.davis@example.org,1986-12-28",
          "3,PHZ9SYAJ23,Alex Davis,jane.brown@example.org,1976-11-06",
          "4,NS8EQ0MR1A,Jane Martinez,katie.garcia@example.org,2000-10-18",
        },
        changes = {
          {
            type = "modify",
            line = 2,
            after = "1,XUMMW,Jane Davis,jane.williams@example.org,1964-03-22",
          },
        },
        expected = {
          "Index  ,ID          ,Name           ,Email                      ,Birthday    ",
          "      1,XUMMW       ,Jane Davis     ,jane.williams@example.org  ,1964-03-22  ",
          "      2,CFLFGKJX4M  ,John Martinez  ,emily.davis@example.org    ,1986-12-28  ",
          "      3,PHZ9SYAJ23  ,Alex Davis     ,jane.brown@example.org     ,1976-11-06  ",
          "      4,NS8EQ0MR1A  ,Jane Martinez  ,katie.garcia@example.org   ,2000-10-18  ",
        },
      },
      {
        name = "renders correctly when column width shrinks",
        lines = {
          "Index,ID,Name,Email,Birthday",
          "1,XUMMW7737A,Jane Davis,jane.williams@example.org,1964-03-22",
          "2,CFLFGKJX4M,John Martinez,emily.davis@example.org,1986-12-28",
          "3,PHZ9SYAJ23,Alex Davis,jane.brown@example.org,1976-11-06",
          "4,NS8EQ0MR1A,Jane Martinez,katie.garcia@example.org,2000-10-18",
        },
        changes = {
          {
            type = "modify",
            line = 2,
            after = "1,XUMMW7737Axxxxxxxx,Jane Davis,jane.williams@example.org,1964-03-22",
          },
        },
        expected = {
          "Index  ,ID                  ,Name           ,Email                      ,Birthday    ",
          "      1,XUMMW7737Axxxxxxxx  ,Jane Davis     ,jane.williams@example.org  ,1964-03-22  ",
          "      2,CFLFGKJX4M          ,John Martinez  ,emily.davis@example.org    ,1986-12-28  ",
          "      3,PHZ9SYAJ23          ,Alex Davis     ,jane.brown@example.org     ,1976-11-06  ",
          "      4,NS8EQ0MR1A          ,Jane Martinez  ,katie.garcia@example.org   ,2000-10-18  ",
        },
      },
    },
  },
  -----------------------------------------------------------
  -- Column Add/Remove
  -----------------------------------------------------------
  {
    describe = "and adding or removing a column",
    cases = {
      {
        name = "renders correctly when a new column is added",
        lines = {
          "Index,ID,Name,Email,Birthday",
          "1,XUMMW7737A,Jane Davis,jane.williams@example.org,1964-03-22",
          "2,CFLFGKJX4M,John Martinez,emily.davis@example.org,1986-12-28",
          "3,PHZ9SYAJ23,Alex Davis,jane.brown@example.org,1976-11-06",
          "4,NS8EQ0MR1A,Jane Martinez,katie.garcia@example.org,2000-10-18",
        },
        changes = {
          {
            type = "modify",
            line = 1,
            after = "Index,ID,Name,Email,Birthday,Age",
          },
        },
        expected = {
          "Index  ,ID          ,Name           ,Email                      ,Birthday    ,Age    ",
          "      1,XUMMW7737A  ,Jane Davis     ,jane.williams@example.org  ,1964-03-22  ",
          "      2,CFLFGKJX4M  ,John Martinez  ,emily.davis@example.org    ,1986-12-28  ",
          "      3,PHZ9SYAJ23  ,Alex Davis     ,jane.brown@example.org     ,1976-11-06  ",
          "      4,NS8EQ0MR1A  ,Jane Martinez  ,katie.garcia@example.org   ,2000-10-18  ",
        },
      },
      {
        name = "renders correctly when a column is removed",
        lines = {
          "Index,ID,Name,Email,Birthday",
          "1,XUMMW7737A,Jane Davis,jane.williams@example.org,1964-03-22",
          "2,CFLFGKJX4M,John Martinez,emily.davis@example.org,1986-12-28",
          "3,PHZ9SYAJ23,Alex Davis,jane.brown@example.org,1976-11-06",
          "4,NS8EQ0MR1A,Jane Martinez,katie.garcia@example.org,2000-10-18",
        },
        changes = {
          {
            type = "modify",
            line = 2,
            after = "1,XUMMW7737A,Jane Davisjane.williams@example.org,1964-03-22",
          },
        },
        expected = {
          "Index  ,ID          ,Name                                 ,Email                     ,Birthday    ",
          "      1,XUMMW7737A  ,Jane Davisjane.williams@example.org  ,1964-03-22                ",
          "      2,CFLFGKJX4M  ,John Martinez                        ,emily.davis@example.org   ,1986-12-28  ",
          "      3,PHZ9SYAJ23  ,Alex Davis                           ,jane.brown@example.org    ,1976-11-06  ",
          "      4,NS8EQ0MR1A  ,Jane Martinez                        ,katie.garcia@example.org  ,2000-10-18  ",
        },
      },
    },
  },
  -----------------------------------------------------------
  -- Line Insert/Delete
  -----------------------------------------------------------
  {
    describe = "and inserting or deleting lines",
    cases = {
      {
        name = "renders correctly when a new line is added and column width grows",
        lines = {
          "Index,ID,Name,Email,Birthday",
          "1,XUMMW7737A,Jane Davis,jane.williams@example.org,1964-03-22",
          "2,CFLFGKJX4M,John Martinez,emily.davis@example.org,1986-12-28",
          "3,PHZ9SYAJ23,Alex Davis,jane.brown@example.org,1976-11-06",
          "4,NS8EQ0MR1A,Jane Martinez,katie.garcia@example.org,2000-10-18",
        },
        changes = {
          {
            type = "insert",
            line = 2,
            after = "0,ABC0000000000,John Doe",
          },
        },
        expected = {
          "Index  ,ID             ,Name           ,Email                      ,Birthday    ",
          "      0,ABC0000000000  ,John Doe       ",
          "      1,XUMMW7737A     ,Jane Davis     ,jane.williams@example.org  ,1964-03-22  ",
          "      2,CFLFGKJX4M     ,John Martinez  ,emily.davis@example.org    ,1986-12-28  ",
          "      3,PHZ9SYAJ23     ,Alex Davis     ,jane.brown@example.org     ,1976-11-06  ",
          "      4,NS8EQ0MR1A     ,Jane Martinez  ,katie.garcia@example.org   ,2000-10-18  ",
        },
      },
      {
        name = "renders correctly when a new line is added and it is the first line",
        lines = {
          "1,XUMMW7737A,Jane Davis,jane.williams@example.org,1964-03-22",
          "2,CFLFGKJX4M,John Martinez,emily.davis@example.org,1986-12-28",
          "3,PHZ9SYAJ23,Alex Davis,jane.brown@example.org,1976-11-06",
          "4,NS8EQ0MR1A,Jane Martinez,katie.garcia@example.org,2000-10-18",
        },
        changes = {
          {
            type = "insert",
            line = 1,
            after = "Index,ID,Name,Email,Birthday",
          },
        },
        expected = {
          "Index  ,ID          ,Name           ,Email                      ,Birthday    ",
          "      1,XUMMW7737A  ,Jane Davis     ,jane.williams@example.org  ,1964-03-22  ",
          "      2,CFLFGKJX4M  ,John Martinez  ,emily.davis@example.org    ,1986-12-28  ",
          "      3,PHZ9SYAJ23  ,Alex Davis     ,jane.brown@example.org     ,1976-11-06  ",
          "      4,NS8EQ0MR1A  ,Jane Martinez  ,katie.garcia@example.org   ,2000-10-18  ",
        },
      },
      {
        name = "renders correctly when a new line is added and it is the last line",
        lines = {
          "Index,ID,Name,Email,Birthday",
          "1,XUMMW7737A,Jane Davis,jane.williams@example.org,1964-03-22",
          "2,CFLFGKJX4M,John Martinez,emily.davis@example.org,1986-12-28",
          "3,PHZ9SYAJ23,Alex Davis,jane.brown@example.org,1976-11-06",
        },
        changes = {
          {
            type = "insert",
            line = 5,
            after = "4,NS8EQ0MR1A,Jane Martinez,katie.garcia@example.org,2000-10-18",
          },
        },
        expected = {
          "Index  ,ID          ,Name           ,Email                      ,Birthday    ",
          "      1,XUMMW7737A  ,Jane Davis     ,jane.williams@example.org  ,1964-03-22  ",
          "      2,CFLFGKJX4M  ,John Martinez  ,emily.davis@example.org    ,1986-12-28  ",
          "      3,PHZ9SYAJ23  ,Alex Davis     ,jane.brown@example.org     ,1976-11-06  ",
          "      4,NS8EQ0MR1A  ,Jane Martinez  ,katie.garcia@example.org   ,2000-10-18  ",
        },
      },
      {
        name = "renders correctly when a line is removed and column width shrinks",
        lines = {
          "Index,ID,Name,Email,Birthday",
          "1,XUMMW7737A,Jane Davis,jane.williams@example.org,1964-03-22",
          "2,CFLFGKJX4M,John Martinez,emily.davis@example.org,1986-12-28",
          "3,PHZ9SYAJ23,Alex Davis,jane.brown@example.org,1976-11-06",
          "4,NS8EQ0MR1A,Jane Martinez,katie.garcia@example.org,2000-10-18",
        },
        changes = { {
          type = "delete",
          line = 2,
        } },
        expected = {
          "Index  ,ID          ,Name           ,Email                     ,Birthday    ",
          "      2,CFLFGKJX4M  ,John Martinez  ,emily.davis@example.org   ,1986-12-28  ",
          "      3,PHZ9SYAJ23  ,Alex Davis     ,jane.brown@example.org    ,1976-11-06  ",
          "      4,NS8EQ0MR1A  ,Jane Martinez  ,katie.garcia@example.org  ,2000-10-18  ",
        },
      },
      {
        name = "renders correctly when a line is removed and it is the first line",
        lines = {
          "Index,ID,Name,Email,Birthday",
          "1,XUMMW7737A,Jane Davis,jane.williams@example.org,1964-03-22",
          "2,CFLFGKJX4M,John Martinez,emily.davis@example.org,1986-12-28",
          "3,PHZ9SYAJ23,Alex Davis,jane.brown@example.org,1976-11-06",
          "4,NS8EQ0MR1A,Jane Martinez,katie.garcia@example.org,2000-10-18",
        },
        changes = { {
          type = "delete",
          line = 1,
        } },
        expected = {
          "      1,XUMMW7737A  ,Jane Davis     ,jane.williams@example.org  ,1964-03-22  ",
          "      2,CFLFGKJX4M  ,John Martinez  ,emily.davis@example.org    ,1986-12-28  ",
          "      3,PHZ9SYAJ23  ,Alex Davis     ,jane.brown@example.org     ,1976-11-06  ",
          "      4,NS8EQ0MR1A  ,Jane Martinez  ,katie.garcia@example.org   ,2000-10-18  ",
        },
      },
      {
        name = "renders correctly when a line is removed and it is the last line",
        lines = {
          "Index,ID,Name,Email,Birthday",
          "1,XUMMW7737A,Jane Davis,jane.williams@example.org,1964-03-22",
          "2,CFLFGKJX4M,John Martinez,emily.davis@example.org,1986-12-28",
          "3,PHZ9SYAJ23,Alex Davis,jane.brown@example.org,1976-11-06",
          "4,NS8EQ0MR1A,Jane Martinez,katie.garcia@example.org,2000-10-18",
        },
        changes = { {
          type = "delete",
          line = 5,
        } },
        expected = {
          "Index  ,ID          ,Name           ,Email                      ,Birthday    ",
          "      1,XUMMW7737A  ,Jane Davis     ,jane.williams@example.org  ,1964-03-22  ",
          "      2,CFLFGKJX4M  ,John Martinez  ,emily.davis@example.org    ,1986-12-28  ",
          "      3,PHZ9SYAJ23  ,Alex Davis     ,jane.brown@example.org     ,1976-11-06  ",
        },
      },
      {
        name = "renders correctly when all lines are removed",
        lines = {
          "Index,ID,Name,Email,Birthday",
          "1,XUMMW7737A,Jane Davis,jane.williams@example.org,1964-03-22",
          "2,CFLFGKJX4M,John Martinez,emily.davis@example.org,1986-12-28",
          "3,PHZ9SYAJ23,Alex Davis,jane.brown@example.org,1976-11-06",
          "4,NS8EQ0MR1A,Jane Martinez,katie.garcia@example.org,2000-10-18",
        },
        changes = {
          { type = "delete", line = 5 },
          { type = "delete", line = 4 },
          { type = "delete", line = 3 },
          { type = "delete", line = 2 },
          { type = "delete", line = 1 },
          { type = "modify", line = 1, after = "a,b,c,d,e" },
        },
        expected = {
          "a      ,b      ,c      ,d      ,e      ",
        },
      },
    },
  },
  -----------------------------------------------------------
  -- Comment/Uncomment
  -----------------------------------------------------------
  {
    describe = "and commenting or uncommenting lines",
    cases = {
      {
        name = "renders correctly when a line is commented",
        lines = {
          "Index,ID,Name,Email,Birthday",
          "1,XUMMW7737A,Jane Davis,jane.williams@example.org,1964-03-22",
          "2,CFLFGKJX4M,John Martinez,emily.davis@example.org,1986-12-28",
          "3,PHZ9SYAJ23,Alex Davis,jane.brown@example.org,1976-11-06",
          "4,NS8EQ0MR1A,Jane Martinez,katie.garcia@example.org,2000-10-18",
        },
        changes = {
          {
            type = "modify",
            line = 1,
            after = "#Index,ID,Name,Email,Birthday",
          },
        },
        expected = {
          "#Index,ID,Name,Email,Birthday",
          "      1,XUMMW7737A  ,Jane Davis     ,jane.williams@example.org  ,1964-03-22  ",
          "      2,CFLFGKJX4M  ,John Martinez  ,emily.davis@example.org    ,1986-12-28  ",
          "      3,PHZ9SYAJ23  ,Alex Davis     ,jane.brown@example.org     ,1976-11-06  ",
          "      4,NS8EQ0MR1A  ,Jane Martinez  ,katie.garcia@example.org   ,2000-10-18  ",
        },
      },
      {
        name = "renders correctly when a line is uncommented",
        lines = {
          "# this is comment, so it should be ignored",
          "Index,ID,Name,Email,Birthday",
          "1,XUMMW7737A,Jane Davis,jane.williams@example.org,1964-03-22",
          "2,CFLFGKJX4M,John Martinez,emily.davis@example.org,1986-12-28",
          "3,PHZ9SYAJ23,Alex Davis,jane.brown@example.org,1976-11-06",
          "4,NS8EQ0MR1A,Jane Martinez,katie.garcia@example.org,2000-10-18",
        },
        changes = {
          {
            type = "modify",
            line = 1,
            after = "this is not a comment, so it should not be ignored",
          },
        },
        expected = {
          "this is not a comment  , so it should not be ignored  ",
          "Index                  ,ID                            ,Name           ,Email                      ,Birthday    ",
          "                      1,XUMMW7737A                    ,Jane Davis     ,jane.williams@example.org  ,1964-03-22  ",
          "                      2,CFLFGKJX4M                    ,John Martinez  ,emily.davis@example.org    ,1986-12-28  ",
          "                      3,PHZ9SYAJ23                    ,Alex Davis     ,jane.brown@example.org     ,1976-11-06  ",
          "                      4,NS8EQ0MR1A                    ,Jane Martinez  ,katie.garcia@example.org   ,2000-10-18  ",
        },
      },
    },
  },
  -----------------------------------------------------------
  -- Quote/Unquote
  -----------------------------------------------------------
  {
    describe = "and quoting or unquoting lines",
    cases = {
      {
        name = "renders correctly when a line is quoted",
        lines = {
          "Index,ID,Name,Email,Birthday",
          "1,XUMMW7737A,Jane Davis,jane.williams@example.org,1964-03-22",
          "2,CFLFGKJX4M,John Martinez,emily.davis@example.org,1986-12-28",
          "3,PHZ9SYAJ23,Alex Davis,jane.brown@example.org,1976-11-06",
          "4,NS8EQ0MR1A,Jane Martinez,katie.garcia@example.org,2000-10-18",
        },
        changes = {
          {
            type = "modify",
            line = 1,
            after = '"Index,ID,Name,Email,Birthday"',
          },
        },
        expected = {
          '"Index,ID,Name,Email,Birthday"  ',
          "                               1,XUMMW7737A  ,Jane Davis     ,jane.williams@example.org  ,1964-03-22  ",
          "                               2,CFLFGKJX4M  ,John Martinez  ,emily.davis@example.org    ,1986-12-28  ",
          "                               3,PHZ9SYAJ23  ,Alex Davis     ,jane.brown@example.org     ,1976-11-06  ",
          "                               4,NS8EQ0MR1A  ,Jane Martinez  ,katie.garcia@example.org   ,2000-10-18  ",
        },
      },
      {
        name = "renders correctly when a line is unquoted",
        lines = {
          '"Index,ID,Name,Email,Birthday"',
          "1,XUMMW7737A,Jane Davis,jane.williams@example.org,1964-03-22",
          "2,CFLFGKJX4M,John Martinez,emily.davis@example.org,1986-12-28",
          "3,PHZ9SYAJ23,Alex Davis,jane.brown@example.org,1976-11-06",
          "4,NS8EQ0MR1A,Jane Martinez,katie.garcia@example.org,2000-10-18",
        },
        changes = {
          {
            type = "modify",
            line = 1,
            after = "Index,ID,Name,Email,Birthday",
          },
        },
        expected = {
          "Index  ,ID          ,Name           ,Email                      ,Birthday    ",
          "      1,XUMMW7737A  ,Jane Davis     ,jane.williams@example.org  ,1964-03-22  ",
          "      2,CFLFGKJX4M  ,John Martinez  ,emily.davis@example.org    ,1986-12-28  ",
          "      3,PHZ9SYAJ23  ,Alex Davis     ,jane.brown@example.org     ,1976-11-06  ",
          "      4,NS8EQ0MR1A  ,Jane Martinez  ,katie.garcia@example.org   ,2000-10-18  ",
        },
      },
    },
  },
}
