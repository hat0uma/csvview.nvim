-----------------------------------------------------------------------------
-- Row
--
-- A read-only view of one line of the metrics store, for callers that are not
-- on a hot path. It is valid until the next metrics update.
-----------------------------------------------------------------------------
local KIND = require("csvview.metrics_store").KIND

local TYPE_NAMES = {
  [KIND.COMMENT] = "comment",
  [KIND.SINGLELINE] = "singleline",
  [KIND.MULTILINE_START] = "multiline_start",
  [KIND.MULTILINE_CONTINUATION] = "multiline_continuation",
}

--- @class CsvView.Metrics.Field
--- @field offset integer 0-based byte offset
--- @field len integer byte length
--- @field display_width integer
--- @field is_number boolean

--- @class CsvView.Metrics.Row
--- @field type "comment" | "singleline" | "multiline_start" | "multiline_continuation"
--- @field terminated boolean whether the record is terminated; if false, the parser reached the lookahead limit
--- @field start_loffset integer offset from the first line of the record
--- @field end_loffset integer offset to the last line of the record
--- @field skipped_ncol integer number of columns that start on previous lines of the record
--- @field private _store CsvView.MetricsStore
--- @field private _base integer
--- @field private _count integer
local Row = {}
Row.__index = Row

--- Create a view of a line
---@param store CsvView.MetricsStore
---@param lnum integer
---@return CsvView.Metrics.Row?
function Row.new(store, lnum)
  if not store:has_line(lnum) then
    return nil
  end
  local kind = store.kind[lnum]

  return setmetatable({
    type = TYPE_NAMES[kind],
    terminated = store.term[lnum] == 1,
    start_loffset = store.rel[lnum],
    end_loffset = store.span[lnum],
    skipped_ncol = store.col0[lnum],
    _store = store,
    _base = store.base[lnum],
    _count = store.count[lnum],
  }, Row)
end

--- Get the number of fields on the line
---@return integer
function Row:field_count()
  return self._count
end

--- Get the field at the pool index
---@param idx integer
---@return CsvView.Metrics.Field
function Row:_field_at(idx)
  local store = self._store
  return {
    offset = store.off[idx],
    len = store.len[idx],
    display_width = store.width[idx],
    is_number = store.num[idx] == 1,
  }
end

--- Get field by column index
---@param col_idx integer 1-indexed column index
---@return CsvView.Metrics.Field?
function Row:field(col_idx)
  local i = col_idx - self.skipped_ncol - 1
  if i < 0 or i >= self._count then
    return nil
  end
  return self:_field_at(self._base + i)
end

--- Iterate over fields on the line
---@return fun(): integer?, CsvView.Metrics.Field?
function Row:iter()
  local i = 0
  return function()
    if i >= self._count then
      return nil, nil
    end
    local field = self:_field_at(self._base + i)
    i = i + 1
    return self.skipped_ncol + i, field
  end
end

return Row
