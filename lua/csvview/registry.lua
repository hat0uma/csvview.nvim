local chunk_mod = require("csvview.chunk")
local Chunk = chunk_mod.Chunk
local STATE_IN_QUOTE = chunk_mod.STATE_IN_QUOTE
local STATE_NORMAL = chunk_mod.STATE_NORMAL

---@class CsvView.Registry
---@field private _chunks CsvView.Chunk[] List of chunks
---@field private _global_max_widths table<integer, integer> Column index -> global max width
---@field private _max_lookahead integer Circuit breaker: max lines to propagate IN_QUOTE state
local Registry = {}
Registry.__index = Registry

--- Create a new Registry
---@param max_lookahead integer? Circuit breaker limit (default: 100)
---@return CsvView.Registry
function Registry:new(max_lookahead)
  local obj = setmetatable({}, self)
  obj._chunks = {}
  obj._global_max_widths = {}
  obj._max_lookahead = max_lookahead or 100
  return obj
end

--- Get the number of chunks
---@return integer
function Registry:chunk_count()
  return #self._chunks
end

--- Get the total number of physical rows across all chunks
---@return integer
function Registry:physical_row_count()
  local count = 0
  for _, chunk in ipairs(self._chunks) do
    count = count + chunk:row_count()
  end
  return count
end

--- Get the total number of logical rows across all chunks
---@return integer
function Registry:logical_row_count()
  local count = 0
  for _, chunk in ipairs(self._chunks) do
    count = count + chunk:logical_count()
  end
  return count
end

--- Get the global maximum width for a column
---@param col_idx integer 0-indexed column index
---@return integer max_width
function Registry:get_global_max_width(col_idx)
  return self._global_max_widths[col_idx] or 0
end

--- Update a row with new widths and state
---@param physical_lnum integer 1-indexed physical line number
---@param widths integer[] Array of column widths
---@param state integer? State for the row (default: NORMAL)
function Registry:update_row(physical_lnum, widths, state)
  state = state or STATE_NORMAL

  -- Find the chunk containing this physical line
  local chunk, chunk_idx, row_in_chunk = self:_find_chunk_by_physical_line(physical_lnum)

  if not chunk then
    error(string.format("Physical line %d not found in any chunk", physical_lnum))
  end

  -- Update the row in the chunk
  for col = 0, #widths - 1 do
    chunk:set_width(row_in_chunk, col, widths[col + 1] or 0)
  end

  local old_state = chunk:get_state(row_in_chunk)
  if old_state ~= state then
    chunk:set_state(row_in_chunk, state)
  end

  -- Check if we need to rebalance (split/merge)
  self:_rebalance_chunk(chunk_idx)

  -- Update global max widths
  self:_update_global_max_widths()
end

--- Insert a new row at the specified physical line number
---@param physical_lnum integer 1-indexed physical line number (row will be inserted here)
---@param widths integer[] Array of column widths
---@param state integer? State for the new row (default: NORMAL)
function Registry:insert_row(physical_lnum, widths, state)
  state = state or STATE_NORMAL

  if #self._chunks == 0 then
    -- No chunks yet, create the first one
    local chunk = Chunk:new()
    chunk:add_row(widths, state)
    table.insert(self._chunks, chunk)
    self:_update_global_max_widths()
    return
  end

  -- Find the chunk containing this physical line (or the last chunk if beyond end)
  local chunk, chunk_idx, row_in_chunk = self:_find_chunk_by_physical_line(physical_lnum)

  if not chunk then
    -- Beyond the end, add to the last chunk
    chunk = self._chunks[#self._chunks]
    chunk_idx = #self._chunks
    chunk:add_row(widths, state)
  else
    -- Insert into the found chunk
    chunk:insert_row(row_in_chunk, widths, state)
  end

  -- Check if we need to rebalance (split/merge)
  self:_rebalance_chunk(chunk_idx)

  -- Update global max widths
  self:_update_global_max_widths()
end

--- Remove a row at the specified physical line number
---@param physical_lnum integer 1-indexed physical line number
function Registry:remove_row(physical_lnum)
  -- Find the chunk containing this physical line
  local chunk, chunk_idx, row_in_chunk = self:_find_chunk_by_physical_line(physical_lnum)

  if not chunk then
    error(string.format("Physical line %d not found in any chunk", physical_lnum))
  end

  -- Remove the row from the chunk
  chunk:remove_row(row_in_chunk)

  -- If the chunk is now empty, remove it
  if chunk:row_count() == 0 then
    table.remove(self._chunks, chunk_idx)
  else
    -- Check if we need to rebalance (split/merge)
    self:_rebalance_chunk(chunk_idx)
  end

  -- Update global max widths
  self:_update_global_max_widths()
end

--- Convert physical line number to logical row number
---@param physical_lnum integer 1-indexed physical line number
---@return integer? logical_row_num 1-indexed logical row number
function Registry:physical_to_logical(physical_lnum)
  local logical_count = 0
  local current_physical = 0

  for _, chunk in ipairs(self._chunks) do
    for row = 0, chunk:row_count() - 1 do
      current_physical = current_physical + 1

      if current_physical == physical_lnum then
        -- Found the target physical line
        -- Check if this row is a logical row start
        local state = chunk:get_state(row)
        if state == STATE_NORMAL then
          logical_count = logical_count + 1
        end

        -- Need to determine if this is a continuation row
        -- by checking previous rows in the same chunk or previous chunk
        local is_continuation = false
        if row > 0 then
          -- Check previous row in the same chunk
          if chunk:get_state(row - 1) == STATE_IN_QUOTE then
            is_continuation = true
          end
        else
          -- Check last row of previous chunk
          if current_physical > 1 then
            is_continuation = self:_is_continuation_from_previous_chunk(chunk, chunk_idx)
          end
        end

        if is_continuation then
          -- This is a continuation, so it doesn't have its own logical row number
          -- Return the logical row number of the start of this multi-line row
          return logical_count
        else
          return logical_count
        end
      end

      -- Count logical rows
      if chunk:get_state(row) == STATE_NORMAL then
        logical_count = logical_count + 1
      end
    end
  end

  return nil -- Physical line not found
end

--- Helper to check if a chunk starts as a continuation from the previous chunk
---@param chunk CsvView.Chunk
---@param chunk_idx integer 1-indexed chunk index in the _chunks array
---@return boolean
function Registry:_is_continuation_from_previous_chunk(chunk, chunk_idx)
  if chunk_idx == 1 then
    return false
  end

  local prev_chunk = self._chunks[chunk_idx - 1]
  local last_row = prev_chunk:row_count() - 1
  return prev_chunk:get_state(last_row) == STATE_IN_QUOTE
end

--- Convert logical row number to physical line number
---@param logical_row_num integer 1-indexed logical row number
---@return integer? physical_lnum 1-indexed physical line number (start of the logical row)
function Registry:logical_to_physical(logical_row_num)
  local logical_count = 0
  local current_physical = 0

  for chunk_idx, chunk in ipairs(self._chunks) do
    for row = 0, chunk:row_count() - 1 do
      current_physical = current_physical + 1

      -- Logical rows end at NORMAL state rows
      local state = chunk:get_state(row)

      if state == STATE_NORMAL then
        logical_count = logical_count + 1
        if logical_count == logical_row_num then
          -- Found the end of the logical row, now find its start
          -- Walk backward to find where this logical row started
          local start_physical = current_physical
          local search_chunk_idx = chunk_idx
          local search_row = row - 1

          while true do
            local search_chunk = self._chunks[search_chunk_idx]
            if not search_chunk then
              break
            end

            if search_row < 0 then
              -- Move to previous chunk
              search_chunk_idx = search_chunk_idx - 1
              if search_chunk_idx < 1 then
                break
              end
              search_chunk = self._chunks[search_chunk_idx]
              search_row = search_chunk:row_count() - 1
              start_physical = start_physical - 1
            else
              local prev_state = search_chunk:get_state(search_row)
              if prev_state ~= STATE_IN_QUOTE then
                -- Previous row is not IN_QUOTE, so current start_physical is correct
                break
              end
              -- Previous row is IN_QUOTE, so continue backward
              start_physical = start_physical - 1
              search_row = search_row - 1
            end
          end

          return start_physical
        end
      end
    end
  end

  return nil -- Logical row not found
end

--- Get the range of physical lines for a logical row
---@param logical_row_num integer 1-indexed logical row number
---@return integer? start_physical Physical line number where the logical row starts
---@return integer? end_physical Physical line number where the logical row ends
function Registry:get_logical_row_range(logical_row_num)
  local start_physical = self:logical_to_physical(logical_row_num)
  if not start_physical then
    return nil, nil
  end

  -- Find the end of this logical row
  local end_physical = start_physical
  local chunk, chunk_idx, row_in_chunk = self:_find_chunk_by_physical_line(start_physical)

  if not chunk then
    return start_physical, start_physical
  end

  -- Traverse forward until we find a NORMAL state
  local current_physical = start_physical
  local current_chunk_idx = chunk_idx
  local current_row = row_in_chunk

  while true do
    local current_chunk = self._chunks[current_chunk_idx]
    if not current_chunk then
      break
    end

    local state = current_chunk:get_state(current_row)
    if state == STATE_NORMAL then
      end_physical = current_physical
      break
    end

    -- Move to next row
    current_physical = current_physical + 1
    current_row = current_row + 1

    if current_row >= current_chunk:row_count() then
      -- Move to next chunk
      current_chunk_idx = current_chunk_idx + 1
      current_row = 0
    end
  end

  return start_physical, end_physical
end

--- Apply circuit breaker to prevent infinite IN_QUOTE propagation
--- This resets IN_QUOTE states that have propagated beyond max_lookahead
function Registry:apply_circuit_breaker()
  local consecutive_in_quote = 0

  for _, chunk in ipairs(self._chunks) do
    for row = 0, chunk:row_count() - 1 do
      if chunk:get_state(row) == STATE_IN_QUOTE then
        consecutive_in_quote = consecutive_in_quote + 1
        if consecutive_in_quote > self._max_lookahead then
          -- Force reset to NORMAL
          chunk:set_state(row, STATE_NORMAL)
          consecutive_in_quote = 0
        end
      else
        consecutive_in_quote = 0
      end
    end
  end
end

--- Clear all chunks
function Registry:clear()
  self._chunks = {}
  self._global_max_widths = {}
end

-------------------------------------------------------
-- Private methods
-------------------------------------------------------

--- Find the chunk containing the specified physical line number
---@param physical_lnum integer 1-indexed physical line number
---@return CsvView.Chunk? chunk The chunk containing the line
---@return integer? chunk_idx 1-indexed chunk index in the _chunks array
---@return integer? row_in_chunk 0-indexed row index within the chunk
function Registry:_find_chunk_by_physical_line(physical_lnum)
  local current_physical = 0

  for chunk_idx, chunk in ipairs(self._chunks) do
    local chunk_row_count = chunk:row_count()
    if physical_lnum <= current_physical + chunk_row_count then
      local row_in_chunk = physical_lnum - current_physical - 1
      return chunk, chunk_idx, row_in_chunk
    end
    current_physical = current_physical + chunk_row_count
  end

  return nil, nil, nil
end

--- Get the index of a chunk in the _chunks array
---@param target_chunk CsvView.Chunk
---@return integer? chunk_idx 1-indexed chunk index
function Registry:_get_chunk_index(target_chunk)
  for idx, chunk in ipairs(self._chunks) do
    if chunk == target_chunk then
      return idx
    end
  end
  return nil
end

--- Update global max widths by aggregating local max widths from all chunks
function Registry:_update_global_max_widths()
  self._global_max_widths = {}

  for _, chunk in ipairs(self._chunks) do
    local col_count = chunk:col_count()
    for col = 0, col_count - 1 do
      local local_max = chunk:get_local_max_width(col)
      local current_global = self._global_max_widths[col] or 0
      if local_max > current_global then
        self._global_max_widths[col] = local_max
      end
    end
  end
end

--- Rebalance a chunk (split if too large, merge if too small)
---@param chunk_idx integer 1-indexed chunk index
function Registry:_rebalance_chunk(chunk_idx)
  local chunk = self._chunks[chunk_idx]

  if chunk:should_split() then
    -- Split the chunk
    local split_point = math.floor(chunk:row_count() / 2)
    local first, second = chunk:split(split_point)

    -- Replace the original chunk with the two new chunks
    self._chunks[chunk_idx] = first
    table.insert(self._chunks, chunk_idx + 1, second)
  elseif chunk:should_merge() then
    -- Try to merge with adjacent chunk
    local adjacent_idx = chunk_idx < #self._chunks and chunk_idx + 1 or chunk_idx - 1

    if adjacent_idx > 0 and adjacent_idx <= #self._chunks then
      local adjacent = self._chunks[adjacent_idx]

      -- Merge the two chunks
      local merged
      if chunk_idx < adjacent_idx then
        merged = chunk:merge(adjacent)
        table.remove(self._chunks, adjacent_idx)
        self._chunks[chunk_idx] = merged
      else
        merged = adjacent:merge(chunk)
        table.remove(self._chunks, chunk_idx)
        self._chunks[adjacent_idx] = merged
      end
    end
  end
end

return {
  Registry = Registry,
}
