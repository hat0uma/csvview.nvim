-----------------------------------------------------------------------------
-- Metrics Store
--
-- Flat storage for the parsed layout of a buffer, as FFI arrays (structure of arrays).
--
--   * Line arrays, indexed by 1-based lnum (valid for `1 <= lnum <= n`).
--     Inserting or removing lines shifts them with memmove.
--   * Field pool, 0-based. A line refers to its fields as the contiguous slice
--     `[base, base + count)`. The pool is append-only: re-parsing a line appends a
--     new slice and abandons the old one, and the pool is compacted once the
--     abandoned slots outweigh the live ones.
--
-- Nothing is allocated per line or per field, so building the store for a large
-- buffer stays inside JIT-compiled code. The arrays live outside the Lua heap
-- (malloc/realloc), so growing them neither zero-fills memory nor puts pressure
-- on the garbage collector.
-----------------------------------------------------------------------------
local ffi = require("ffi")

-- Another plugin may have declared these already.
pcall(ffi.cdef, "void *malloc(size_t size);")
pcall(ffi.cdef, "void *realloc(void *ptr, size_t size);")
pcall(ffi.cdef, "void free(void *ptr);")
pcall(ffi.cdef, "void *memmove(void *dest, const void *src, size_t n);")

local INITIAL_CAPACITY = 8192

--- Line kinds.
local KIND = {
  COMMENT = 0,
  SINGLELINE = 1,
  MULTILINE_START = 2,
  MULTILINE_CONTINUATION = 3,
}

--- Array layouts: { field name, element ctype, element size }
local LINE_ARRAYS = {
  { "kind", "uint8_t*", 1 },
  { "term", "uint8_t*", 1 },
  { "base", "int32_t*", 4 },
  { "count", "int32_t*", 4 },
  { "col0", "int32_t*", 4 },
  { "rel", "int32_t*", 4 },
  { "span", "int32_t*", 4 },
}
local FIELD_ARRAYS = {
  { "off", "int32_t*", 4 },
  { "len", "int32_t*", 4 },
  { "width", "int32_t*", 4 },
  { "num", "uint8_t*", 1 },
}

--- @class CsvView.MetricsStore
--- @field n integer number of lines
--- @field kind ffi.cdata* uint8_t* line kind (see `KIND`)
--- @field term ffi.cdata* uint8_t* 1 if the record the line belongs to is terminated
--- @field base ffi.cdata* int32_t* pool index of the first field of the line
--- @field count ffi.cdata* int32_t* number of fields on the line
--- @field col0 ffi.cdata* int32_t* column index of the first field on the line, minus 1
--- @field rel ffi.cdata* int32_t* offset from the first line of the record (0 for its first line)
--- @field span ffi.cdata* int32_t* offset to the last line of the record (0 for its last line)
--- @field off ffi.cdata* int32_t* 0-based byte offset of the field
--- @field len ffi.cdata* int32_t* byte length of the field
--- @field width ffi.cdata* int32_t* display width of the field
--- @field num ffi.cdata* uint8_t* 1 if the field is a number
--- @field used integer number of pool slots in use (live or abandoned)
--- @field live integer number of pool slots referenced by lines
--- @field private _line_cap integer
--- @field private _field_cap integer
local Store = {}
Store.__index = Store
Store.KIND = KIND

--- Resize an array, keeping its contents.
---@param ptr ffi.cdata*? current array, or nil to allocate a new one
---@param ctype string
---@param elem_size integer
---@param cap integer new capacity
---@return ffi.cdata*
local function realloc_array(ptr, ctype, elem_size, cap)
  local raw
  if ptr == nil then
    raw = ffi.C.malloc(cap * elem_size)
  else
    ffi.gc(ptr, nil) -- ownership moves to realloc
    raw = ffi.C.realloc(ptr, cap * elem_size)
  end
  if raw == nil then
    error("csvview: out of memory")
  end
  return ffi.gc(ffi.cast(ctype, raw), ffi.C.free)
end

--- Resize a group of arrays
---@param store CsvView.MetricsStore
---@param layout table
---@param cap integer
local function resize(store, layout, cap)
  for _, a in ipairs(layout) do
    store[a[1]] = realloc_array(store[a[1]], a[2], a[3], cap)
  end
end

--- Create a new store
---@return CsvView.MetricsStore
function Store.new()
  local self = setmetatable({}, Store)
  self:clear()
  return self
end

--- Remove all lines and fields
function Store:clear()
  for _, a in ipairs(LINE_ARRAYS) do
    self[a[1]] = nil
  end
  for _, a in ipairs(FIELD_ARRAYS) do
    self[a[1]] = nil
  end
  self.n = 0
  self._line_cap = INITIAL_CAPACITY
  resize(self, LINE_ARRAYS, self._line_cap + 1) -- 1-based
  self.used = 0
  self.live = 0
  self._field_cap = INITIAL_CAPACITY
  resize(self, FIELD_ARRAYS, self._field_cap)
end

--- Ensure line arrays can hold `n` lines
---@param n integer
function Store:_reserve_lines(n)
  if n <= self._line_cap then
    return
  end
  local cap = self._line_cap
  while cap < n do
    cap = cap * 2
  end
  self._line_cap = cap
  resize(self, LINE_ARRAYS, cap + 1)
end

--- Whether the line exists
---@param lnum integer
---@return boolean
function Store:has_line(lnum)
  return lnum >= 1 and lnum <= self.n
end

--- Append a field to the pool.
---@param offset integer 0-based byte offset
---@param len integer byte length
---@param width integer display width
---@param is_number boolean
---@return integer idx pool index of the field
function Store:push_field(offset, len, width, is_number)
  local idx = self.used
  if idx >= self._field_cap then
    self._field_cap = self._field_cap * 2
    resize(self, FIELD_ARRAYS, self._field_cap)
  end
  self.off[idx] = offset
  self.len[idx] = len
  self.width[idx] = width
  self.num[idx] = is_number and 1 or 0
  self.used = idx + 1
  return idx
end

--- Set the layout of a line. `lnum` is an existing line, or the line after the last one.
---@param lnum integer
---@param kind integer
---@param base integer
---@param count integer
---@param col0 integer
---@param rel integer
---@param span integer
---@param term boolean
function Store:set_line(lnum, kind, base, count, col0, rel, span, term)
  if lnum < 1 then
    error(string.format("line out of range: lnum=%d", lnum))
  elseif lnum > self.n then
    assert(lnum == self.n + 1, "lines must be appended in order")
    self:_reserve_lines(lnum)
    self.n = lnum
  else
    self.live = self.live - self.count[lnum]
  end
  self.live = self.live + count

  self.kind[lnum] = kind
  self.term[lnum] = term and 1 or 0
  self.base[lnum] = base
  self.count[lnum] = count
  self.col0[lnum] = col0
  self.rel[lnum] = rel
  self.span[lnum] = span
end

--- Move lines `[first, n]` to start at `dest`.
---@param first integer
---@param dest integer
function Store:_move_lines(first, dest)
  local num = self.n - first + 1
  if num <= 0 then
    return
  end
  for _, a in ipairs(LINE_ARRAYS) do
    local arr = self[a[1]]
    ffi.C.memmove(arr + dest, arr + first, num * a[3])
  end
end

--- Insert `num` empty lines before `start`.
---@param start integer
---@param num integer
function Store:insert_lines(start, num)
  assert(start >= 1 and start <= self.n + 1, "insert position out of range")
  self:_reserve_lines(self.n + num)
  self:_move_lines(start, start + num)
  for lnum = start, start + num - 1 do
    self.kind[lnum] = KIND.SINGLELINE
    self.term[lnum] = 1
    self.base[lnum] = 0
    self.count[lnum] = 0
    self.col0[lnum] = 0
    self.rel[lnum] = 0
    self.span[lnum] = 0
  end
  self.n = self.n + num
end

--- Remove `num` lines starting at `start`.
---@param start integer
---@param num integer
function Store:remove_lines(start, num)
  num = math.min(num, self.n - start + 1)
  if num <= 0 then
    return
  end

  for lnum = start, start + num - 1 do
    self.live = self.live - self.count[lnum]
  end
  self:_move_lines(start + num, start)
  self.n = self.n - num
end

--- Compact the pool when abandoned slots outweigh the live ones.
function Store:maybe_compact()
  if self.used <= INITIAL_CAPACITY or self.used <= self.live * 2 then
    return
  end

  local cap = INITIAL_CAPACITY
  while cap < self.live do
    cap = cap * 2
  end

  -- Copy the live slices, in line order, into fresh arrays.
  local s_off, s_len, s_width, s_num = self.off, self.len, self.width, self.num
  for _, a in ipairs(FIELD_ARRAYS) do
    self[a[1]] = nil
  end
  self._field_cap = cap
  resize(self, FIELD_ARRAYS, cap)
  local off, len, width, num = self.off, self.len, self.width, self.num

  local base, count = self.base, self.count
  local pos = 0
  for lnum = 1, self.n do
    local b, c = base[lnum], count[lnum]
    base[lnum] = pos
    for i = 0, c - 1 do
      off[pos] = s_off[b + i]
      len[pos] = s_len[b + i]
      width[pos] = s_width[b + i]
      num[pos] = s_num[b + i]
      pos = pos + 1
    end
  end

  self.used = pos
  self.live = pos
end

return Store
