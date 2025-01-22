local M = {}

local buf = require("csvview.buf")
local util = require("csvview.util")

--- Clamps a value between a minimum and maximum.
---@param value number
---@param min number
---@param max number
---@return number
local function clamp(value, min, max)
  return math.min(math.max(value, min), max)
end

--- Checks if a row is skippable for `opts.col_wrap`.
---@param metrics CsvView.Metrics
---@param row_idx integer
---@return boolean
local function is_skippable_row(metrics, row_idx)
  local row = metrics.rows[row_idx]
  if row.is_comment or #row.fields == 0 then
    return true
  end

  return false
end

--- Wraps around columns when moving beyond the last column
---@param metrics CsvView.Metrics
---@param row_idx integer
---@param col_idx integer
---@param relative_col integer relative column offset
---@return integer row_idx, integer col_idx
local function wrap_column(metrics, row_idx, col_idx, relative_col)
  local rest = math.abs(relative_col)
  local direction = (relative_col > 0) and 1 or -1

  -- While we still have columns to move (rest)...
  while rest > 0 do
    local row = metrics.rows[row_idx]
    if not row then
      -- We've gone beyond valid rows, so break out
      break
    end

    -- Check if we're trying to move before the first column
    if col_idx + direction < 1 then
      if row_idx == 1 then
        -- Already at the first row, clamp to first col
        row_idx = 1
        col_idx = 1
        break
      end

      -- Move to the previous row
      row_idx = row_idx - 1

      -- If the previous row is non-empty, move to the last field
      -- Otherwise, you might want to decrement rest or skip further empty rows
      if not is_skippable_row(metrics, row_idx) then
        col_idx = #metrics.rows[row_idx].fields
        rest = rest - 1
      end

    -- Check if we're trying to move beyond the last column
    elseif col_idx + direction > #row.fields then
      if row_idx == #metrics.rows then
        -- Already at the last row, clamp to last col
        row_idx = #metrics.rows
        col_idx = #row.fields
        break
      end

      -- Move to the next row
      row_idx = row_idx + 1

      -- If the next row is non-empty, move to the first field
      -- Otherwise, you might want to decrement rest or skip further empty rows
      if not is_skippable_row(metrics, row_idx) then
        col_idx = 1
        rest = rest - 1
      end
    else
      -- Move horizontally within the row
      col_idx = col_idx + direction
      rest = rest - 1
    end
  end

  -- If we land exactly on an empty field at the end of a line,
  -- we might need to move to the next row. This recursion is a neat trick but watch for infinite loops!
  if col_idx ~= 0 and metrics:is_last_col(row_idx, col_idx) and metrics:is_empty_field(row_idx, col_idx) then
    row_idx, col_idx = wrap_column(metrics, row_idx, col_idx, direction)
  end

  return row_idx, col_idx
end

--- Move to the next row that has a field at the specified column index.
---@param metrics CsvView.Metrics
---@param row_idx integer
---@param col_idx integer
---@param direction integer
---@return integer
local function move_to_next_row(metrics, row_idx, col_idx, direction)
  local row = metrics.rows[row_idx]
  if not row then
    return row_idx
  end

  local next_row_idx = row_idx
  while true do
    next_row_idx = next_row_idx + direction
    if not metrics:is_valid_row(next_row_idx) then
      return row_idx
    end

    local next_row = metrics.rows[next_row_idx]
    if #next_row.fields >= col_idx then
      return next_row_idx
    end
  end
end

--- Get the destination row and column for a jump operation.
---@param bufnr integer
---@param metrics CsvView.Metrics
---@param opts CsvView.JumpOpts
---@return integer row_idx, integer col_idx
local function get_jump_destination(bufnr, metrics, opts)
  --- @type integer,integer 1-indexed row and column indices
  local row_idx, col_idx

  -- Ensure that the cursor is within the CSV view
  if opts.mode == "relative" then
    local cursor = util.get_cursor(bufnr)
    local cursor_row, cursor_col = cursor.pos[1], cursor.pos[2]

    row_idx = cursor_row
    col_idx = cursor_col or 1
    local row_delta = opts.pos[1]
    local col_delta = opts.pos[2]

    -- Calculate row
    for _ = 1, math.abs(row_delta) do
      local direction = (row_delta > 0) and 1 or -1
      row_idx = move_to_next_row(metrics, row_idx, col_idx, direction)
    end

    -- Calculate column
    if opts.col_wrap then
      row_idx, col_idx = wrap_column(metrics, row_idx, col_idx, col_delta)
    else
      col_idx = col_idx + col_delta
    end
  else
    row_idx, col_idx = opts.pos[1], opts.pos[2]
  end

  return row_idx, col_idx
end

---
--- @class CsvView.JumpOpts
---
--- Coordinates for jumping, specified as {row, col}.
--- - If `mode` is `"relative"`, `pos` represents offsets from the current position (can be negative).
--- - If `mode` is `"absolute"`, `pos` is 1-based coordinates {row, col}.
---
--- (default: `{0, 1}` (which moves to the next column)).
--- @field pos? integer[]
---
--- Determines how `pos` is interpreted.
--- - `"relative"`: interprets `pos` as offsets from the current position.
--- - `"absolute"`: interprets `pos` as absolute row and column numbers (1-based).
---
--- (default: `"relative"`).
--- @field mode? "relative" | "absolute"
---
--- Determines where the cursor will be placed within the target field.
--- - `"start"`: places the cursor at the beginning of the field.
--- - `"end"`: places the cursor at the end of the field.
---
--- (default: `"start"`).
--- @field anchor? "start" | "end"
---
--- If `true`, wraps around columns when moving beyond the last column
--- (or before the first column if using negative offsets).
--- Valid only when `mode` is `"relative"`.
---
--- (default: `true`).
---
--- For example with a CSV like(* indicates the cursor position):
---
--- 1: A1,B1,C1*
--- 2: A2,B2,C2
--- 3: A3,B3,C3
--- ```lua
--- jump(0, { pos = {0, 1}, col_wrap = true }) -- jump to A2
--- jump(0, { pos = {0, 1}, col_wrap = false }) -- no jump
--- ```
--- @field col_wrap? boolean

--- Moves the cursor to a field according to the specified options.
---
--- ### Basic Usage Examples
--- ```lua
--- -- 1) Simply move to the next column (relative)
--- jump()
---
--- -- 2) Move 2 rows down, 1 column left
--- jump(0, { pos = {2, -1} })
---
--- -- 3) Jump to (row=10, col=3) absolutely
--- jump(0, { pos = {10, 3}, mode = "absolute" })
--- ```
---@param bufnr? integer
---@param opts? CsvView.JumpOpts
function M.jump(bufnr, opts)
  bufnr = buf.resolve_bufnr(bufnr)

  -- Set default options
  ---@type CsvView.JumpOpts
  opts = vim.tbl_extend("force", {
    pos = { 0, 1 },
    mode = "relative",
    anchor = "start",
    col_wrap = true,
  }, opts or {})

  -- Check validity of options
  assert(opts.mode == "relative" or opts.mode == "absolute", "Mode must be 'relative' or 'absolute'")
  assert(opts.anchor == "start" or opts.anchor == "end", "Mode must be 'start' or 'end'")
  assert(type(opts.pos) == "table", "Position must be a table of two integers")
  assert(type(opts.pos[1]) == "number", "Position[1] must be a number")
  assert(type(opts.pos[2]) == "number", "Position[2] must be a number")
  assert(type(opts.col_wrap) == "boolean", "col_wrap must be a boolean")

  -- Get the corresponding view for this buffer
  local view = require("csvview.view").get(bufnr)
  if not view then
    vim.notify("csvview: not enabled for this buffer.")
    return
  end

  -- Get the window ID for the buffer
  local winid = buf.get_win(bufnr)
  if not winid then
    error("Window not found for buffer " .. bufnr)
  end

  -- Calculate the destination row and column
  local metrics = view.metrics
  local row_idx, col_idx = get_jump_destination(bufnr, metrics, opts)

  -- Clamp row and column indices
  row_idx = clamp(row_idx, 1, #metrics.rows)
  col_idx = clamp(col_idx, 1, #metrics.rows[row_idx].fields)

  -- If the line is empty or comment, set the cursor to the beginning of the line
  if #metrics.rows[row_idx].fields == 0 then
    vim.api.nvim_win_set_cursor(winid, { row_idx, 0 })
    return
  end

  -- Update cursor position
  local offset, field_len = metrics:col_idx_to_byte(row_idx, col_idx)
  local anchored_col --- @type integer
  if opts.anchor == "start" then
    anchored_col = offset
  else
    anchored_col = offset + math.max(0, field_len - 1)
  end
  vim.api.nvim_win_set_cursor(winid, { row_idx, anchored_col })
end

--- Moves the cursor to the next end of the field
--- like `e` motion in normal mode.
---@param bufnr integer?
function M.jump_to_next_end_of_field(bufnr)
  local cursor = util.get_cursor(bufnr)

  local opts = { anchor = "end" } ---@type CsvView.JumpOpts
  if cursor.kind == "field" then
    local charlen = vim.fn.charidx(cursor.text, #cursor.text)
    local col_increases = {
      start = charlen == 1 and 1 or 0,
      inside = 0,
      ["end"] = 1,
      delimiter = 1,
    }
    opts.pos = { 0, col_increases[cursor.anchor] }
  else
    opts.pos = { 0, 1 }
  end

  -- jump to the end of the previous field
  M.jump(bufnr, opts)
end

--- Moves the cursor to the previous end of the field.
--- like `ge` motion in normal mode.
--- @param bufnr integer?
function M.jump_to_prev_end_of_field(bufnr)
  local cursor = util.get_cursor(bufnr)

  local opts = { anchor = "end" } ---@type CsvView.JumpOpts
  if cursor.kind == "field" then
    local charlen = vim.fn.charidx(cursor.text, #cursor.text)
    local col_increases = {
      start = charlen == 1 and -1 or 0,
      inside = -1,
      ["end"] = -1,
      delimiter = #cursor.text == 0 and -1 or 0,
    }
    opts.pos = { 0, col_increases[cursor.anchor] }
  else
    opts.pos = { 0, -1 }
  end

  -- jump to the end of the previous field
  M.jump(bufnr, opts)
end

--- Moves the cursor to the next start of the field.
--- like `w` motion in normal mode.
--- @param bufnr integer?
function M.jump_to_next_start_of_field(bufnr)
  M.jump(bufnr, { pos = { 0, 1 }, anchor = "start" })
end

--- Moves the cursor to the previous start of the field.
--- like `b` motion in normal mode.
--- @param bufnr integer?
function M.jump_to_prev_start_of_field(bufnr)
  local cursor = util.get_cursor(bufnr)

  local opts = { anchor = "start" } ---@type CsvView.JumpOpts
  if cursor.kind == "field" then
    local col_increases = {
      start = -1,
      inside = 0,
      ["end"] = 0,
      delimiter = #cursor.text == 0 and -1 or 0,
    }
    opts.pos = { 0, col_increases[cursor.anchor] }
  else
    opts.pos = { 0, -1 }
  end

  -- jump to the end of the previous field
  M.jump(bufnr, opts)
end

return M
