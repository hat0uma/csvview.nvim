local ffi = require("ffi")

-- FFI type definitions
ffi.cdef([[
  typedef struct {
    int32_t *data;      // Flattened array: [row1_col1, row1_col2, ..., row2_col1, ...]
    uint8_t *states;    // Parse state for each row: 0=IN_QUOTE, 1=NORMAL
    int32_t capacity;   // Allocated capacity for rows
    int32_t row_count;  // Current number of rows
    int32_t col_count;  // Number of columns
  } chunk_data_t;

  void *memcpy(void *dest, const void *src, size_t n);
  void *memmove(void *dest, const void *src, size_t n);
]])

-- Constants
local STATE_IN_QUOTE = 0
local STATE_NORMAL = 1

-- Configuration
local DEFAULT_CHUNK_SIZE = 100
local SPLIT_THRESHOLD = 200
local MERGE_THRESHOLD = 50

---@class CsvView.Chunk
---@field private _data ffi.cdata* Pointer to chunk_data_t
---@field private _local_max_widths table<integer, integer> Column index -> max width in this chunk
---@field private _logical_count integer Number of logical rows (rows in NORMAL state)
local Chunk = {}
Chunk.__index = Chunk

--- Create a new Chunk
---@param capacity integer? Initial capacity (default: 100)
---@param col_count integer? Number of columns (default: 0)
---@return CsvView.Chunk
function Chunk:new(capacity, col_count)
  capacity = capacity or DEFAULT_CHUNK_SIZE
  col_count = col_count or 0

  local data = ffi.new("chunk_data_t")
  data.capacity = capacity
  data.row_count = 0
  data.col_count = col_count
  data.data = ffi.new("int32_t[?]", capacity * math.max(1, col_count))
  data.states = ffi.new("uint8_t[?]", capacity)

  -- Initialize states to NORMAL
  for i = 0, capacity - 1 do
    data.states[i] = STATE_NORMAL
  end

  local obj = setmetatable({}, self)
  obj._data = data
  obj._local_max_widths = {}
  obj._logical_count = 0

  return obj
end

--- Get the number of rows in this chunk
---@return integer
function Chunk:row_count()
  return tonumber(self._data.row_count)
end

--- Get the number of columns
---@return integer
function Chunk:col_count()
  return tonumber(self._data.col_count)
end

--- Get the number of logical rows (rows in NORMAL state)
---@return integer
function Chunk:logical_count()
  return self._logical_count
end

--- Get the state of a row
---@param row_idx integer 0-indexed row index
---@return integer state 0=IN_QUOTE, 1=NORMAL
function Chunk:get_state(row_idx)
  assert(row_idx >= 0 and row_idx < self._data.row_count, "Row index out of bounds")
  return tonumber(self._data.states[row_idx])
end

--- Set the state of a row
---@param row_idx integer 0-indexed row index
---@param state integer 0=IN_QUOTE, 1=NORMAL
function Chunk:set_state(row_idx, state)
  assert(row_idx >= 0 and row_idx < self._data.row_count, "Row index out of bounds")
  assert(state == STATE_IN_QUOTE or state == STATE_NORMAL, "Invalid state")

  local old_state = self._data.states[row_idx]
  self._data.states[row_idx] = state

  -- Update logical count
  if old_state == STATE_IN_QUOTE and state == STATE_NORMAL then
    self._logical_count = self._logical_count + 1
  elseif old_state == STATE_NORMAL and state == STATE_IN_QUOTE then
    self._logical_count = self._logical_count - 1
  end
end

--- Get the width of a specific cell
---@param row_idx integer 0-indexed row index
---@param col_idx integer 0-indexed column index
---@return integer width
function Chunk:get_width(row_idx, col_idx)
  assert(row_idx >= 0 and row_idx < self._data.row_count, "Row index out of bounds")
  assert(col_idx >= 0 and col_idx < self._data.col_count, "Column index out of bounds")

  local offset = row_idx * self._data.col_count + col_idx
  return tonumber(self._data.data[offset])
end

--- Set the width of a specific cell
---@param row_idx integer 0-indexed row index
---@param col_idx integer 0-indexed column index
---@param width integer
function Chunk:set_width(row_idx, col_idx, width)
  assert(row_idx >= 0 and row_idx < self._data.row_count, "Row index out of bounds")
  assert(col_idx >= 0 and col_idx < self._data.col_count, "Column index out of bounds")
  assert(width >= 0, "Width must be non-negative")

  local offset = row_idx * self._data.col_count + col_idx
  local old_width = self._data.data[offset]
  self._data.data[offset] = width

  -- Update local max width
  local current_max = self._local_max_widths[col_idx] or 0
  if width > current_max then
    self._local_max_widths[col_idx] = width
  elseif old_width == current_max and width < old_width then
    -- If we're shrinking the max value, mark for recalculation
    self._local_max_widths[col_idx] = nil
  end
end

--- Get the local maximum width for a column
---@param col_idx integer 0-indexed column index
---@return integer max_width
function Chunk:get_local_max_width(col_idx)
  -- If cached, return it
  if self._local_max_widths[col_idx] then
    return self._local_max_widths[col_idx]
  end

  -- Otherwise, recalculate
  local max_width = 0
  for row = 0, self._data.row_count - 1 do
    local offset = row * self._data.col_count + col_idx
    local width = tonumber(self._data.data[offset])
    if width > max_width then
      max_width = width
    end
  end

  self._local_max_widths[col_idx] = max_width
  return max_width
end

--- Add a new row to the chunk
---@param widths integer[] Array of column widths for the new row
---@param state integer? State for the new row (default: NORMAL)
function Chunk:add_row(widths, state)
  state = state or STATE_NORMAL

  -- Ensure capacity
  if self._data.row_count >= self._data.capacity then
    self:_grow()
  end

  -- Adjust column count if necessary
  local new_col_count = #widths
  if new_col_count > self._data.col_count then
    self:_adjust_columns(new_col_count)
  end

  -- Add the row
  local row_idx = self._data.row_count
  for col = 0, new_col_count - 1 do
    local offset = row_idx * self._data.col_count + col
    self._data.data[offset] = widths[col + 1] or 0
  end

  self._data.states[row_idx] = state
  self._data.row_count = self._data.row_count + 1

  -- Update logical count and local max widths
  if state == STATE_NORMAL then
    self._logical_count = self._logical_count + 1
  end

  for col = 0, new_col_count - 1 do
    local width = widths[col + 1] or 0
    local current_max = self._local_max_widths[col] or 0
    if width > current_max then
      self._local_max_widths[col] = width
    end
  end
end

--- Insert a row at a specific index
---@param row_idx integer 0-indexed row index
---@param widths integer[] Array of column widths for the new row
---@param state integer? State for the new row (default: NORMAL)
function Chunk:insert_row(row_idx, widths, state)
  assert(row_idx >= 0 and row_idx <= self._data.row_count, "Row index out of bounds")
  state = state or STATE_NORMAL

  -- Ensure capacity
  if self._data.row_count >= self._data.capacity then
    self:_grow()
  end

  -- Adjust column count if necessary
  local new_col_count = #widths
  if new_col_count > self._data.col_count then
    self:_adjust_columns(new_col_count)
  end

  -- Shift rows down using memmove
  if row_idx < self._data.row_count then
    local src_offset = row_idx * self._data.col_count
    local dst_offset = (row_idx + 1) * self._data.col_count
    local count = (self._data.row_count - row_idx) * self._data.col_count
    ffi.C.memmove(
      self._data.data + dst_offset,
      self._data.data + src_offset,
      count * ffi.sizeof("int32_t")
    )

    -- Shift states
    ffi.C.memmove(
      self._data.states + row_idx + 1,
      self._data.states + row_idx,
      (self._data.row_count - row_idx) * ffi.sizeof("uint8_t")
    )
  end

  -- Insert the new row
  for col = 0, new_col_count - 1 do
    local offset = row_idx * self._data.col_count + col
    self._data.data[offset] = widths[col + 1] or 0
  end

  self._data.states[row_idx] = state
  self._data.row_count = self._data.row_count + 1

  -- Update logical count
  if state == STATE_NORMAL then
    self._logical_count = self._logical_count + 1
  end

  -- Invalidate local max widths (they need to be recalculated)
  self._local_max_widths = {}
end

--- Remove a row from the chunk
---@param row_idx integer 0-indexed row index
function Chunk:remove_row(row_idx)
  assert(row_idx >= 0 and row_idx < self._data.row_count, "Row index out of bounds")

  -- Update logical count
  if self._data.states[row_idx] == STATE_NORMAL then
    self._logical_count = self._logical_count - 1
  end

  -- Shift rows up using memmove
  if row_idx < self._data.row_count - 1 then
    local dst_offset = row_idx * self._data.col_count
    local src_offset = (row_idx + 1) * self._data.col_count
    local count = (self._data.row_count - row_idx - 1) * self._data.col_count
    ffi.C.memmove(
      self._data.data + dst_offset,
      self._data.data + src_offset,
      count * ffi.sizeof("int32_t")
    )

    -- Shift states
    ffi.C.memmove(
      self._data.states + row_idx,
      self._data.states + row_idx + 1,
      (self._data.row_count - row_idx - 1) * ffi.sizeof("uint8_t")
    )
  end

  self._data.row_count = self._data.row_count - 1

  -- Invalidate local max widths (they need to be recalculated)
  self._local_max_widths = {}
end

--- Rescan the chunk to recalculate local max widths and logical count
function Chunk:rescan()
  self._local_max_widths = {}
  self._logical_count = 0

  for row = 0, self._data.row_count - 1 do
    -- Update logical count
    if self._data.states[row] == STATE_NORMAL then
      self._logical_count = self._logical_count + 1
    end

    -- Update local max widths
    for col = 0, self._data.col_count - 1 do
      local offset = row * self._data.col_count + col
      local width = tonumber(self._data.data[offset])
      local current_max = self._local_max_widths[col] or 0
      if width > current_max then
        self._local_max_widths[col] = width
      end
    end
  end
end

--- Check if this chunk should be split
---@return boolean
function Chunk:should_split()
  return self._data.row_count > SPLIT_THRESHOLD
end

--- Check if this chunk should be merged with adjacent chunks
---@return boolean
function Chunk:should_merge()
  return self._data.row_count < MERGE_THRESHOLD
end

--- Split this chunk into two chunks at the specified row index
---@param split_at integer 0-indexed row index where to split (this row goes to the second chunk)
---@return CsvView.Chunk first_chunk
---@return CsvView.Chunk second_chunk
function Chunk:split(split_at)
  assert(split_at > 0 and split_at < self._data.row_count, "Invalid split point")

  -- Create two new chunks
  local first = Chunk:new(split_at + 10, self._data.col_count)
  local second = Chunk:new(self._data.row_count - split_at + 10, self._data.col_count)

  -- Copy data to first chunk
  for row = 0, split_at - 1 do
    local widths = {}
    for col = 0, self._data.col_count - 1 do
      widths[col + 1] = self:get_width(row, col)
    end
    first:add_row(widths, self._data.states[row])
  end

  -- Copy data to second chunk
  for row = split_at, self._data.row_count - 1 do
    local widths = {}
    for col = 0, self._data.col_count - 1 do
      widths[col + 1] = self:get_width(row, col)
    end
    second:add_row(widths, self._data.states[row])
  end

  -- Rescan both chunks
  first:rescan()
  second:rescan()

  return first, second
end

--- Merge this chunk with another chunk
---@param other CsvView.Chunk The chunk to merge with
---@return CsvView.Chunk merged_chunk
function Chunk:merge(other)
  local total_rows = self._data.row_count + other._data.row_count
  local max_cols = math.max(self._data.col_count, other._data.col_count)

  local merged = Chunk:new(total_rows + 10, max_cols)

  -- Copy data from this chunk
  for row = 0, self._data.row_count - 1 do
    local widths = {}
    for col = 0, self._data.col_count - 1 do
      widths[col + 1] = self:get_width(row, col)
    end
    merged:add_row(widths, self._data.states[row])
  end

  -- Copy data from other chunk
  for row = 0, other._data.row_count - 1 do
    local widths = {}
    for col = 0, other._data.col_count - 1 do
      widths[col + 1] = other:get_width(row, col)
    end
    merged:add_row(widths, other._data.states[row])
  end

  -- Rescan merged chunk
  merged:rescan()

  return merged
end

--- Grow the chunk capacity (internal helper)
function Chunk:_grow()
  local new_capacity = self._data.capacity * 2
  local new_data = ffi.new("int32_t[?]", new_capacity * self._data.col_count)
  local new_states = ffi.new("uint8_t[?]", new_capacity)

  -- Copy existing data
  ffi.C.memcpy(
    new_data,
    self._data.data,
    self._data.row_count * self._data.col_count * ffi.sizeof("int32_t")
  )
  ffi.C.memcpy(
    new_states,
    self._data.states,
    self._data.row_count * ffi.sizeof("uint8_t")
  )

  -- Initialize new states to NORMAL
  for i = self._data.row_count, new_capacity - 1 do
    new_states[i] = STATE_NORMAL
  end

  self._data.data = new_data
  self._data.states = new_states
  self._data.capacity = new_capacity
end

--- Adjust column count (internal helper)
---@param new_col_count integer
function Chunk:_adjust_columns(new_col_count)
  if new_col_count <= self._data.col_count then
    return
  end

  local new_data = ffi.new("int32_t[?]", self._data.capacity * new_col_count)

  -- Copy existing data with new column layout
  for row = 0, self._data.row_count - 1 do
    for col = 0, self._data.col_count - 1 do
      local old_offset = row * self._data.col_count + col
      local new_offset = row * new_col_count + col
      new_data[new_offset] = self._data.data[old_offset]
    end
    -- Initialize new columns to 0
    for col = self._data.col_count, new_col_count - 1 do
      local new_offset = row * new_col_count + col
      new_data[new_offset] = 0
    end
  end

  self._data.data = new_data
  self._data.col_count = new_col_count
end

return {
  Chunk = Chunk,
  STATE_IN_QUOTE = STATE_IN_QUOTE,
  STATE_NORMAL = STATE_NORMAL,
  SPLIT_THRESHOLD = SPLIT_THRESHOLD,
  MERGE_THRESHOLD = MERGE_THRESHOLD,
}
