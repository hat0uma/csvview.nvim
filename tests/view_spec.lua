local CsvViewMetrics = require("csvview.metrics")
local config = require("csvview.config")
local csvview = require("csvview")
local view = require("csvview.view")

--- Get lines extmarks applied
---@param bufnr integer
---@param ns integer
---@return string[]
local function get_lines_with_extmarks(bufnr, ns)
  -- get lines and extmarks
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
  local col_offset = {} --- @type integer[]
  for _, extmark in ipairs(extmarks) do
    local row = extmark[2] --- @type integer
    local col = extmark[3] --- @type integer
    local details = extmark[4] --- @type { virt_text: string[][]?, virt_text_pos: string? }
    local lnum = row + 1
    if details.virt_text_pos == "inline" then
      for _, virt_text in pairs(details.virt_text) do
        col_offset[lnum] = col_offset[lnum] or 0
        local prefix = lines[lnum]:sub(0, col + col_offset[lnum])
        local suffix = lines[lnum]:sub(col + col_offset[lnum] + 1)
        lines[lnum] = prefix .. virt_text[1] .. suffix
        col_offset[lnum] = col_offset[lnum] + #virt_text[1]
      end
    elseif details.virt_text_pos == "overlay" then
      local virt_text = details.virt_text[1][1]
      col_offset[lnum] = col_offset[lnum] or 0
      local prefix = lines[lnum]:sub(1, col + col_offset[lnum])
      local suffix = lines[lnum]:sub(col + col_offset[lnum] + 1 + vim.fn.strdisplaywidth(virt_text))
      lines[lnum] = prefix .. virt_text .. suffix
      col_offset[lnum] = col_offset[lnum] + #virt_text - vim.fn.strdisplaywidth(virt_text)
    end
  end

  return lines
end

describe("view", function()
  config.setup()
  csvview.setup()
  local ns = vim.api.nvim_get_namespaces()["csv_extmark"]
  describe("CsvView:render", function()
    describe("should align correctly even if it contains multibyte characters", function()
      -- define test cases
      --- @type table<string, {opts: CsvViewOptions, lines: string[], expected: string[]}>
      local cases = {
        ["display_mode  = 'highlight'"] = {
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
        ["display_mode  = 'border'"] = {
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

      -- run test cases.
      for name, c in pairs(cases) do
        it(name, function() ---@async
          -- create buffer and set lines
          local bufnr = vim.api.nvim_create_buf(false, true)
          local opts = config.get(c.opts)
          local lines = c.lines
          local expected = c.expected
          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

          -- compute metrics
          local co = coroutine.running()
          local metrics = CsvViewMetrics:new(bufnr, opts)
          metrics:compute_buffer(function()
            vim.schedule(function()
              coroutine.resume(co)
            end)
          end)

          -- wait for the completion of the metrics computation
          coroutine.yield()

          -- create view and render
          local winid = vim.api.nvim_get_current_win()
          vim.api.nvim_win_set_buf(winid, bufnr)
          local v = view.CsvView:new(bufnr, metrics, opts)
          v:render(1, vim.api.nvim_buf_line_count(bufnr), winid)

          -- check the result
          local actual = get_lines_with_extmarks(bufnr, ns)
          for i, line in ipairs(actual) do
            assert.are.same(expected[i], line)
          end
        end)
      end
    end)
  end)
end)
