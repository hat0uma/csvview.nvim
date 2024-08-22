local config = require("csvview.config")
local csvview = require("csvview")
local metrics = require("csvview.metrics")
local view = require("csvview.view")

--- get lines with extmarks
---@param bufnr integer
---@param ns integer
---@return string[]
local function get_lines_with_extmarks(bufnr, ns)
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
  csvview.setup()
  local ns = vim.api.nvim_get_namespaces()["csv_extmark"]
  describe("CsvView:render", function()
    describe("should align correctly even if it contains multibyte characters", function()
      it("display_mode = 'highlight'", function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        local opts = config.get({
          view = {
            min_column_width = 5,
            spacing = 1,
            display_mode = "highlight",
          },
        })
        local lines = {
          "column1(number),column2(emoji),column3(string)",
          "111,😀,abcde",
          "222222222222,😒😒😒😒,fgh",
          "333333333333333333,😎b😎b😎b😎b😎b😎b,ijk",
        }
        local expected = {
          "column1(number)    ,column2(emoji)     ,column3(string) ",
          "                111,😀                 ,abcde           ",
          "       222222222222,😒😒😒😒           ,fgh             ",
          " 333333333333333333,😎b😎b😎b😎b😎b😎b ,ijk             ",
        }

        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
        local co = coroutine.running()
        metrics.compute_csv_metrics(bufnr, opts, function(fields, column_max_widths)
          local v = view.CsvView:new(bufnr, fields, column_max_widths, opts)

          -- test
          v:render(1, vim.api.nvim_buf_line_count(bufnr))
          local actual = get_lines_with_extmarks(bufnr, ns)
          for i, line in ipairs(actual) do
            assert.are.same(expected[i], line)
          end
          vim.schedule(function()
            coroutine.resume(co)
          end)
        end)

        coroutine.yield()
      end)

      it("display_mode = 'border'", function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        local opts = config.get({
          view = {
            min_column_width = 5,
            spacing = 1,
            display_mode = "border",
          },
        })
        local lines = {
          "column1(number),column2(emoji),column3(string)",
          "111,😀,abcde",
          "222222222222,😒😒😒😒,fgh",
          "333333333333333333,😎b😎b😎b😎b😎b😎b,ijk",
        }
        local expected = {
          "column1(number)    │column2(emoji)     │column3(string) ",
          "                111│😀                 │abcde           ",
          "       222222222222│😒😒😒😒           │fgh             ",
          " 333333333333333333│😎b😎b😎b😎b😎b😎b │ijk             ",
        }

        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
        local co = coroutine.running()
        metrics.compute_csv_metrics(bufnr, opts, function(fields, column_max_widths)
          local v = view.CsvView:new(bufnr, fields, column_max_widths, opts)

          -- test
          v:render(1, vim.api.nvim_buf_line_count(bufnr))
          local actual = get_lines_with_extmarks(bufnr, ns)
          for i, line in ipairs(actual) do
            assert.are.same(expected[i], line)
          end
          vim.schedule(function()
            coroutine.resume(co)
          end)
        end)

        coroutine.yield()
      end)
    end)
  end)
end)
