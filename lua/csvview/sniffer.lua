local M = {}

---@class CsvView.Sniffer.Dialect
---@field delimiter string The detected delimiter character
---@field quote_char string The detected quote character
---@field header_lnum integer? The line number of the header row, if detected

local DEFAULT_DELIMITERS = { ",", "\t", ";", "|", ":", " " }
local DEFAULT_QUOTE_CHARS = { '"', "'" }

---
---@class CsvView.Sniffer.SniffOptions
---
---@field delimiter string | string[] | nil Delimiter character to use, or nil to auto-detect
---
---@field quote_char string | string[] | nil Quote character to use, or nil to auto-detect
---
---@field comments string[]
---
---@field max_lookahead integer Maximum lookahead for parsing

---Sniff CSV dialect from the buffer
---@param sample_lines string[] Sample lines to use instead of the buffer
---@param opts CsvView.Sniffer.SniffOptions
---@return CsvView.Sniffer.Dialect dialect The detected CSV dialect
function M.sniff(sample_lines, opts)
  local dialect = {}

  -- Detect quote character
  local quote_char = opts.quote_char
  if type(quote_char) == "string" then
    dialect.quote_char = quote_char
  elseif type(quote_char) == "table" then
    dialect.quote_char = M._detect_quote_char(sample_lines, quote_char)
  else
    dialect.quote_char = M._detect_quote_char(sample_lines, DEFAULT_QUOTE_CHARS)
  end

  -- Detect delimiter
  local delimiter = opts.delimiter
  if type(delimiter) == "string" then
    dialect.delimiter = delimiter
  else
    local candidate_delimiters = type(delimiter) == "table" and delimiter or DEFAULT_DELIMITERS
    dialect.delimiter = M._detect_delimiter(
      sample_lines,
      candidate_delimiters,
      dialect.quote_char,
      opts.comments,
      opts.max_lookahead --
    )
  end

  -- Detect header
  dialect.header_lnum = M._detect_header(
    sample_lines,
    dialect.delimiter,
    dialect.quote_char,
    opts.comments,
    opts.max_lookahead --
  )

  return dialect
end

--- Create a parser for the given sample lines
---@param sample_lines string[] Sample lines to use instead of the buffer
---@param delimiter string The delimiter character
---@param quote_char string The quote character
---@param comments string[] Comments to ignores
---@param max_lookahead integer Maximum lookahead for parsing
---@return CsvView.Parser parser The parser instance
local function create_parser(sample_lines, delimiter, quote_char, comments, max_lookahead)
  return require("csvview.parser"):new_with_source(quote_char:byte(), delimiter, comments, max_lookahead, {
    get_line = function(lnum)
      return sample_lines[lnum]
    end,
    get_line_count = function()
      return #sample_lines
    end,
  })
end

---Calculate consistency score for a delimiter across multiple lines
---@param sample_lines string[] Sample lines to analyze
---@param delimiter string The delimiter character
---@param quote_char string The quote character
---@param comments string[] Comments to ignore
---@param max_lookahead integer Maximum lookahead for parsing
---@return number score Consistency score (0-1, higher is better)
function M._calculate_consistency_score(sample_lines, delimiter, quote_char, comments, max_lookahead)
  local lines_to_check = #sample_lines
  local parser = create_parser(sample_lines, delimiter, quote_char, comments, max_lookahead)

  local field_counts = {} ---@type integer[]
  local total_fields = 0
  local records_count = 0

  local lnum = 1
  while lnum <= lines_to_check do
    local is_comment, fields, line_end = parser:parse_line(lnum)

    -- Skip comment lines
    if not is_comment and #fields > 0 then
      local n_fields = #fields
      table.insert(field_counts, n_fields)
      total_fields = total_fields + n_fields
      records_count = records_count + 1
    end

    -- Move to the next line
    lnum = line_end + 1
  end

  -- Need at least 2 records to calculate consistency
  if records_count < 2 then
    return 0
  end

  local avg_fields = total_fields / records_count

  -- Skip if average is too low (likely not a valid delimiter)
  if avg_fields < 2 then
    return 0
  end

  -- Calculate variance
  local variance = 0
  for _, count in ipairs(field_counts) do
    variance = variance + (count - avg_fields) ^ 2
  end
  variance = variance / records_count

  -- Convert variance to consistency score (lower variance = higher consistency)
  -- Use exponential decay to heavily penalize high variance
  local consistency_score = math.exp(-variance / avg_fields)

  return consistency_score
end

---Detect quote character by looking for paired quotes
---@param sample_lines string[] Sample lines to analyze
---@param quote_chars string[] Possible quote characters
---@return string quote_char The detected quote character
function M._detect_quote_char(sample_lines, quote_chars)
  local sample = table.concat(sample_lines, "\n")
  local quote_scores = {} ---@type table<string, number>

  for _, quote_char in ipairs(quote_chars) do
    local count = 0
    local in_quote = false
    local quote_byte = quote_char:byte()
    local pos = 1

    while pos <= #sample do
      local char = sample:byte(pos)

      if char == quote_byte then
        if in_quote and pos < #sample and sample:byte(pos + 1) == quote_byte then
          -- Escaped quote, skip next character
          pos = pos + 1
        else
          -- Toggle quote state
          in_quote = not in_quote
          count = count + 1
        end
      end

      pos = pos + 1
    end

    -- Prefer even counts (properly paired quotes)
    local score = count
    if count % 2 == 0 and count > 0 then
      score = score + 100 -- Bonus for even counts
    end

    quote_scores[quote_char] = score
  end

  -- Find the quote character with the highest score
  local best_quote = quote_chars[1]
  local best_score = quote_scores[best_quote] or 0

  for quote_char, score in pairs(quote_scores) do
    if score > best_score then
      best_quote = quote_char
      best_score = score
    end
  end

  return best_quote
end

---Detect delimiter by analyzing field consistency
---@param sample_lines string[] Sample lines to analyze
---@param delimiters string[] Possible delimiter characters
---@param quote_char string The quote character to use
---@param comments string[] Comments to ignore
---@param max_lookahead integer Maximum lookahead for parsing
---@return string delimiter The detected delimiter character
function M._detect_delimiter(sample_lines, delimiters, quote_char, comments, max_lookahead)
  local delimiter_scores = {} ---@type table<string, number> -- Store scores for each delimiter

  for _, delimiter in ipairs(delimiters) do
    local consistency_score =
      M._calculate_consistency_score(sample_lines, delimiter, quote_char, comments, max_lookahead)
    delimiter_scores[delimiter] = consistency_score
  end

  -- Find the delimiter with the highest consistency score
  local best_delimiter = delimiters[1]
  local best_score = delimiter_scores[best_delimiter]

  for delimiter, score in pairs(delimiter_scores) do
    if score > best_score then
      best_delimiter = delimiter
      best_score = score
    end
  end

  return best_delimiter
end

--- Patterns for detecting date formats
local DATE_PATTERNS = {
  -- YYYY-MM-DD HH:MM:SS
  "^(%d%d%d%d)-(%d%d)-(%d%d) (%d%d):(%d%d):(%d%d)$",
  -- YYYY/MM/DD HH:MM:SS
  "^(%d%d%d%d)/(%d%d)/(%d%d) (%d%d):(%d%d):(%d%d)$",
  -- YYYY-MM-DD
  "^(%d%d%d%d)-(%d%d)-(%d%d)$",
  -- YYYY/MM/DD
  "^(%d%d%d%d)/(%d%d)/(%d%d)$",
  -- MM-DD-YYYY
  "^(%d%d)-(%d%d)-(%d%d%d%d)$",
  -- MM/DD/YYYY
  "^(%d%d)/(%d%d)/(%d%d%d%d)$",
}

-- Boolean text representations
local BOOLEAN_TEXT = {
  "true",
  "false",
  "0",
  "1",
  "yes",
  "no",
  "on",
  "off",
  "t",
  "f",
  "y",
  "n",
}

--- @type table<string, fun(text: string): boolean>
local FIELD_TYPE_VALIDATORS = {
  numeric = function(text)
    -- nullable numbers are considered numeric"
    return #text == 0 or tonumber(text) ~= nil
  end,

  boolean = function(text)
    return vim.list_contains(BOOLEAN_TEXT, text:lower())
  end,

  date = function(text)
    for _, pattern in ipairs(DATE_PATTERNS) do
      if text:match(pattern) then
        return true
      end
    end
    return false
  end,
}

--- Transpose fields from rows to columns
---@param data string[][]
---@return string[][]
local function transpose_fields(data)
  local transposed = {} ---@type string[][]

  -- Initialize transposed table with empty lists
  for i = 1, #data[1] do
    transposed[i] = {}
  end

  -- Iterate through each row and append fields to the corresponding column
  for _, row in ipairs(data) do
    for col_idx, value in ipairs(row) do
      if transposed[col_idx] then
        table.insert(transposed[col_idx], value)
      end
    end
  end
  return transposed
end

--- Parse
---@param parser CsvView.Parser
---@param lnum integer
---@return boolean is_comment
---@return string[] parsed_fields
---@return integer line_end
local function parse_line(parser, lnum)
  local fields = {}
  local is_comment, parsed_fields, line_end = parser:parse_line(lnum)
  for _, field in ipairs(parsed_fields) do
    local text = field.text
    if type(text) == "table" then
      table.insert(fields, table.concat(text, "\n"))
    else
      table.insert(fields, text)
    end
  end
  return is_comment, fields, line_end
end

--- Determine the best type for a column based on its data
---@param column_data string[] Data for the column to analyze
---@return string? best_type The best type for the column, or nil if no type matches
local function best_type_for_column(column_data)
  local best_type ---@type string?
  for col_type, type_validator in pairs(FIELD_TYPE_VALIDATORS) do
    if vim.iter(column_data):skip(1):all(type_validator) then
      -- If all values in the column match this type, it is the best type
      best_type = col_type
      break
    end
  end
  return best_type
end

---Detect if the first row is a header
---@param sample_lines string[] Sample lines to analyze
---@param delimiter string The delimiter character
---@param quote_char string The quote character
---@param comments string[] Comments to ignore
---@param max_lookahead integer Maximum lookahead for parsing
---@return integer? header_lnum The line number of the header row, if detected
function M._detect_header(sample_lines, delimiter, quote_char, comments, max_lookahead)
  local line_count = #sample_lines
  if line_count < 2 then
    return nil
  end

  local parser = create_parser(sample_lines, delimiter, quote_char, comments, max_lookahead)

  -- Find the first non-comment line
  local first_valid_lnum ---@type integer?
  local first_fields ---@type string[]
  local first_line_end = 1
  for lnum = 1, line_count do
    local is_comment
    is_comment, first_fields, first_line_end = parse_line(parser, lnum)
    if not is_comment and #first_fields > 0 then
      first_valid_lnum = lnum
      break
    end
  end

  -- No valid lines found
  if not first_valid_lnum then
    return nil
  end

  -- If the first line is multiline, it cannot be a header
  if first_valid_lnum ~= first_line_end then
    return nil
  end

  -- Collect data from subsequent lines
  local data = { first_fields } ---@type string[][]
  for lnum = first_valid_lnum + 1, line_count do
    local is_comment, fields = parse_line(parser, lnum)
    if not is_comment and #fields > 0 then
      table.insert(data, fields)
    end
  end

  -- transpose the data to analyze columns
  local transposed = transpose_fields(data)

  local header_evidence = 0
  for col_idx, column_data in ipairs(transposed) do
    -- Determine the best type for data rows and evaluate the likelihood of being a header.
    local first = column_data[1]
    local best_type = best_type_for_column(column_data)
    if best_type then
      if FIELD_TYPE_VALIDATORS[best_type](first) then
        -- If the first row is also of the same type, it is less likely to be a header
        -- For example, if the first row is numeric and the others are also numeric
        header_evidence = header_evidence - 1
      else
        -- If the first row is of a different type, it is more likely to be a header
        -- For example, if the first row is a string and the others are numeric
        header_evidence = header_evidence + 1
      end
    else
      -- If no consistent type was found, treat it as text
      -- For text, check if all rows except the first have the same length.
      -- This is because it may contain IDs or other unique values.
      local rest = vim.iter(column_data):skip(1)
      local data_row_len = #rest:next()
      if rest:all(function(field)
        return #field == data_row_len
      end) then
        if #first == data_row_len then
          header_evidence = header_evidence - 1
        else
          header_evidence = header_evidence + 1
        end
      end
    end
  end

  if header_evidence > 0 then
    -- If the first row has more evidence of being a header, return its line number
    return first_valid_lnum
  end

  return nil
end

return M
