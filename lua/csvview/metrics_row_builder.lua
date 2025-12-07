local CsvViewMetricsRow = require("csvview.metrics_row")

-----------------------------------------------------------------------------
-- Row Builder Module
-- Responsible for constructing CsvView.Metrics.Row objects from parser output
-----------------------------------------------------------------------------

local M = {}

--- Build field info from parser field
---@param field CsvView.Parser.FieldInfo
---@param field_text string
---@return CsvView.Metrics.Field
local function build_field(field, field_text)
  return {
    offset = field.start_pos - 1,
    len = #field_text,
    display_width = vim.fn.strdisplaywidth(field_text),
    is_number = tonumber(field_text) ~= nil,
  }
end

--- Build field info for multiline field continuation
---@param text string
---@param offset integer
---@return CsvView.Metrics.Field
local function build_multiline_field(text, offset)
  return {
    offset = offset,
    len = #text,
    display_width = vim.fn.strdisplaywidth(text),
    is_number = false,
  }
end

--- Build single line row
---@param parsed_fields CsvView.Parser.FieldInfo[]
---@return CsvView.Metrics.Row[]
local function build_single_row(parsed_fields)
  local row_fields = {} ---@type CsvView.Metrics.Field[]
  for _, field in ipairs(parsed_fields) do
    local field_text = field.text
    assert(type(field_text) == "string")
    table.insert(row_fields, build_field(field, field_text))
  end
  return { CsvViewMetricsRow.new_single_row(row_fields) }
end

--- Build multiline rows
---@param lnum integer line number
---@param parsed_fields CsvView.Parser.FieldInfo[]
---@param parsed_endlnum integer end line number of the parsed row
---@param terminated boolean whether the row is terminated
---@return CsvView.Metrics.Row[]
local function build_multiline_rows(lnum, parsed_fields, parsed_endlnum, terminated)
  local total_rows = parsed_endlnum - lnum + 1
  local row_fields = {} --- @type table<integer, CsvView.Metrics.Field[]>
  local row_skipped_ncol = {} --- @type table<integer, integer>

  -- Initialize field arrays for each row
  for i = 1, total_rows do
    row_fields[i] = {}
    row_skipped_ncol[i] = 0
  end

  -- First pass: distribute fields to rows and calculate skipped columns
  local current_row_index = 1
  for field_index, field in ipairs(parsed_fields) do
    local field_text = field.text

    if type(field_text) == "table" then
      -- Multi-line field
      for i, text in ipairs(field_text) do
        -- first line starts at field.start_pos, others are 0
        local offset = i == 1 and field.start_pos - 1 or 0
        table.insert(row_fields[current_row_index], build_multiline_field(text, offset))

        -- Set skipped columns for continuation rows
        if i > 1 and row_skipped_ncol[current_row_index] == 0 then
          row_skipped_ncol[current_row_index] = field_index - 1
        end

        -- Move to next row if not the last line of this field
        if i ~= #field_text then
          current_row_index = current_row_index + 1
        end
      end
    else
      -- Single-line field
      table.insert(row_fields[current_row_index], build_field(field, field_text))
    end
  end

  -- Second pass: create rows with all fields initialized
  local rows = {} --- @type CsvView.Metrics.Row[]
  for i = 1, total_rows do
    if i == 1 then
      rows[i] = CsvViewMetricsRow.new_multiline_start_row(parsed_endlnum - lnum, terminated, row_fields[i])
    else
      rows[i] = CsvViewMetricsRow.new_multiline_continuation_row(
        i - 1, -- relative start line offset
        parsed_endlnum - lnum - i + 1, -- relative end line offset
        row_skipped_ncol[i],
        terminated,
        row_fields[i]
      )
    end
  end

  return rows
end

--- Construct row metrics from parser output
---@param lnum integer line number
---@param is_comment boolean
---@param parsed_fields CsvView.Parser.FieldInfo[]
---@param parsed_endlnum integer end line number of the parsed row
---@param terminated boolean whether the row is terminated, if false, parser reached lookahead limit
---@return CsvView.Metrics.Row[]
function M.construct_rows(lnum, is_comment, parsed_fields, parsed_endlnum, terminated)
  if is_comment then
    return { CsvViewMetricsRow.new_comment_row() }
  end

  if parsed_endlnum == lnum then
    -- Single line row
    return build_single_row(parsed_fields)
  end

  -- Multi-line row
  return build_multiline_rows(lnum, parsed_fields, parsed_endlnum, terminated)
end

return M
