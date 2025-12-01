local chunk_mod = require("csvview.chunk")
local Chunk = chunk_mod.Chunk
local STATE_IN_QUOTE = chunk_mod.STATE_IN_QUOTE
local STATE_NORMAL = chunk_mod.STATE_NORMAL

describe("Chunk", function()
  describe("initialization", function()
    it("creates a new chunk with default capacity", function()
      local chunk = Chunk:new()
      assert.equals(0, chunk:row_count())
      assert.equals(0, chunk:col_count())
      assert.equals(0, chunk:logical_count())
    end)

    it("creates a new chunk with custom capacity and column count", function()
      local chunk = Chunk:new(50, 5)
      assert.equals(0, chunk:row_count())
      assert.equals(5, chunk:col_count())
      assert.equals(0, chunk:logical_count())
    end)
  end)

  describe("add_row", function()
    it("adds a single row", function()
      local chunk = Chunk:new()
      chunk:add_row({ 10, 20, 30 })

      assert.equals(1, chunk:row_count())
      assert.equals(3, chunk:col_count())
      assert.equals(1, chunk:logical_count())
      assert.equals(10, chunk:get_width(0, 0))
      assert.equals(20, chunk:get_width(0, 1))
      assert.equals(30, chunk:get_width(0, 2))
      assert.equals(STATE_NORMAL, chunk:get_state(0))
    end)

    it("adds multiple rows", function()
      local chunk = Chunk:new()
      chunk:add_row({ 10, 20, 30 })
      chunk:add_row({ 15, 25, 35 })
      chunk:add_row({ 5, 10, 15 })

      assert.equals(3, chunk:row_count())
      assert.equals(3, chunk:logical_count())
      assert.equals(15, chunk:get_width(1, 0))
      assert.equals(25, chunk:get_width(1, 1))
    end)

    it("adds a row with IN_QUOTE state", function()
      local chunk = Chunk:new()
      chunk:add_row({ 10, 20 }, STATE_NORMAL)
      chunk:add_row({ 15, 25 }, STATE_IN_QUOTE)
      chunk:add_row({ 5, 10 }, STATE_NORMAL)

      assert.equals(3, chunk:row_count())
      assert.equals(2, chunk:logical_count()) -- Only NORMAL rows count
      assert.equals(STATE_NORMAL, chunk:get_state(0))
      assert.equals(STATE_IN_QUOTE, chunk:get_state(1))
      assert.equals(STATE_NORMAL, chunk:get_state(2))
    end)

    it("expands columns when adding wider rows", function()
      local chunk = Chunk:new(10, 2)
      chunk:add_row({ 10, 20 })
      chunk:add_row({ 15, 25, 35, 45 }) -- More columns

      assert.equals(2, chunk:row_count())
      assert.equals(4, chunk:col_count())
      assert.equals(35, chunk:get_width(1, 2))
      assert.equals(45, chunk:get_width(1, 3))
    end)
  end)

  describe("insert_row", function()
    it("inserts a row at the beginning", function()
      local chunk = Chunk:new()
      chunk:add_row({ 10, 20 })
      chunk:add_row({ 30, 40 })
      chunk:insert_row(0, { 5, 15 })

      assert.equals(3, chunk:row_count())
      assert.equals(5, chunk:get_width(0, 0))
      assert.equals(15, chunk:get_width(0, 1))
      assert.equals(10, chunk:get_width(1, 0))
      assert.equals(30, chunk:get_width(2, 0))
    end)

    it("inserts a row in the middle", function()
      local chunk = Chunk:new()
      chunk:add_row({ 10, 20 })
      chunk:add_row({ 30, 40 })
      chunk:insert_row(1, { 5, 15 })

      assert.equals(3, chunk:row_count())
      assert.equals(10, chunk:get_width(0, 0))
      assert.equals(5, chunk:get_width(1, 0))
      assert.equals(30, chunk:get_width(2, 0))
    end)

    it("inserts a row at the end", function()
      local chunk = Chunk:new()
      chunk:add_row({ 10, 20 })
      chunk:insert_row(1, { 5, 15 })

      assert.equals(2, chunk:row_count())
      assert.equals(10, chunk:get_width(0, 0))
      assert.equals(5, chunk:get_width(1, 0))
    end)
  end)

  describe("remove_row", function()
    it("removes a row from the beginning", function()
      local chunk = Chunk:new()
      chunk:add_row({ 10, 20 })
      chunk:add_row({ 30, 40 })
      chunk:add_row({ 50, 60 })
      chunk:remove_row(0)

      assert.equals(2, chunk:row_count())
      assert.equals(30, chunk:get_width(0, 0))
      assert.equals(50, chunk:get_width(1, 0))
    end)

    it("removes a row from the middle", function()
      local chunk = Chunk:new()
      chunk:add_row({ 10, 20 })
      chunk:add_row({ 30, 40 })
      chunk:add_row({ 50, 60 })
      chunk:remove_row(1)

      assert.equals(2, chunk:row_count())
      assert.equals(10, chunk:get_width(0, 0))
      assert.equals(50, chunk:get_width(1, 0))
    end)

    it("removes a row from the end", function()
      local chunk = Chunk:new()
      chunk:add_row({ 10, 20 })
      chunk:add_row({ 30, 40 })
      chunk:remove_row(1)

      assert.equals(1, chunk:row_count())
      assert.equals(10, chunk:get_width(0, 0))
    end)

    it("updates logical count when removing NORMAL row", function()
      local chunk = Chunk:new()
      chunk:add_row({ 10, 20 }, STATE_NORMAL)
      chunk:add_row({ 30, 40 }, STATE_IN_QUOTE)
      chunk:add_row({ 50, 60 }, STATE_NORMAL)

      assert.equals(2, chunk:logical_count())
      chunk:remove_row(0) -- Remove NORMAL row
      assert.equals(1, chunk:logical_count())
    end)
  end)

  describe("set_state", function()
    it("changes state from NORMAL to IN_QUOTE", function()
      local chunk = Chunk:new()
      chunk:add_row({ 10, 20 }, STATE_NORMAL)

      assert.equals(1, chunk:logical_count())
      chunk:set_state(0, STATE_IN_QUOTE)
      assert.equals(STATE_IN_QUOTE, chunk:get_state(0))
      assert.equals(0, chunk:logical_count())
    end)

    it("changes state from IN_QUOTE to NORMAL", function()
      local chunk = Chunk:new()
      chunk:add_row({ 10, 20 }, STATE_IN_QUOTE)

      assert.equals(0, chunk:logical_count())
      chunk:set_state(0, STATE_NORMAL)
      assert.equals(STATE_NORMAL, chunk:get_state(0))
      assert.equals(1, chunk:logical_count())
    end)
  end)

  describe("set_width", function()
    it("updates a cell width", function()
      local chunk = Chunk:new()
      chunk:add_row({ 10, 20, 30 })

      chunk:set_width(0, 1, 100)
      assert.equals(100, chunk:get_width(0, 1))
    end)

    it("updates local max width when increasing", function()
      local chunk = Chunk:new()
      chunk:add_row({ 10, 20, 30 })
      chunk:add_row({ 15, 25, 35 })

      assert.equals(25, chunk:get_local_max_width(1))

      chunk:set_width(0, 1, 100)
      assert.equals(100, chunk:get_local_max_width(1))
    end)

    it("invalidates local max width when decreasing max value", function()
      local chunk = Chunk:new()
      chunk:add_row({ 10, 20, 30 })
      chunk:add_row({ 15, 100, 35 }) -- Max for col 1

      assert.equals(100, chunk:get_local_max_width(1))

      chunk:set_width(1, 1, 50) -- Decrease the max value

      -- Max width should be recalculated
      assert.equals(50, chunk:get_local_max_width(1))
    end)
  end)

  describe("get_local_max_width", function()
    it("calculates max width for a column", function()
      local chunk = Chunk:new()
      chunk:add_row({ 10, 20, 30 })
      chunk:add_row({ 15, 100, 35 })
      chunk:add_row({ 5, 50, 40 })

      assert.equals(15, chunk:get_local_max_width(0))
      assert.equals(100, chunk:get_local_max_width(1))
      assert.equals(40, chunk:get_local_max_width(2))
    end)

    it("caches max width for efficiency", function()
      local chunk = Chunk:new()
      chunk:add_row({ 10, 20, 30 })
      chunk:add_row({ 15, 100, 35 })

      local max1 = chunk:get_local_max_width(1)
      local max2 = chunk:get_local_max_width(1) -- Should use cache

      assert.equals(max1, max2)
      assert.equals(100, max1)
    end)
  end)

  describe("rescan", function()
    it("recalculates local max widths and logical count", function()
      local chunk = Chunk:new()
      chunk:add_row({ 10, 20 }, STATE_NORMAL)
      chunk:add_row({ 30, 40 }, STATE_IN_QUOTE)
      chunk:add_row({ 50, 60 }, STATE_NORMAL)

      -- Manually corrupt the data
      chunk._logical_count = 0
      chunk._local_max_widths = {}

      chunk:rescan()

      assert.equals(2, chunk:logical_count())
      assert.equals(50, chunk:get_local_max_width(0))
      assert.equals(60, chunk:get_local_max_width(1))
    end)
  end)

  describe("split and merge", function()
    it("checks if chunk should split", function()
      local chunk = Chunk:new()
      assert.is_false(chunk:should_split())

      -- Add rows beyond SPLIT_THRESHOLD (200)
      for i = 1, 201 do
        chunk:add_row({ i, i * 2 })
      end

      assert.is_true(chunk:should_split())
    end)

    it("checks if chunk should merge", function()
      local chunk = Chunk:new()
      -- Add a few rows (less than MERGE_THRESHOLD of 50)
      for i = 1, 40 do
        chunk:add_row({ i, i * 2 })
      end

      assert.is_true(chunk:should_merge())
    end)

    it("splits a chunk into two", function()
      local chunk = Chunk:new()
      for i = 1, 10 do
        chunk:add_row({ i, i * 2 }, i % 2 == 0 and STATE_IN_QUOTE or STATE_NORMAL)
      end

      local first, second = chunk:split(5)

      assert.equals(5, first:row_count())
      assert.equals(5, second:row_count())
      assert.equals(1, first:get_width(0, 0))
      assert.equals(6, second:get_width(0, 0))

      -- Check logical counts
      assert.equals(3, first:logical_count()) -- rows 0,2,4 are NORMAL
      assert.equals(2, second:logical_count()) -- rows 5,7,9 are NORMAL
    end)

    it("merges two chunks", function()
      local chunk1 = Chunk:new()
      for i = 1, 5 do
        chunk1:add_row({ i, i * 2 })
      end

      local chunk2 = Chunk:new()
      for i = 6, 10 do
        chunk2:add_row({ i, i * 2 })
      end

      local merged = chunk1:merge(chunk2)

      assert.equals(10, merged:row_count())
      assert.equals(10, merged:logical_count())
      assert.equals(1, merged:get_width(0, 0))
      assert.equals(10, merged:get_width(9, 0))
      assert.equals(10, merged:get_local_max_width(0))
      assert.equals(20, merged:get_local_max_width(1))
    end)

    it("merges chunks with different column counts", function()
      local chunk1 = Chunk:new()
      chunk1:add_row({ 10, 20 })

      local chunk2 = Chunk:new()
      chunk2:add_row({ 30, 40, 50, 60 })

      local merged = chunk1:merge(chunk2)

      assert.equals(2, merged:row_count())
      assert.equals(4, merged:col_count())
      assert.equals(10, merged:get_width(0, 0))
      assert.equals(20, merged:get_width(0, 1))
      assert.equals(50, merged:get_width(1, 2))
    end)
  end)

  describe("capacity management", function()
    it("automatically grows capacity when needed", function()
      local chunk = Chunk:new(2, 2) -- Start with capacity of 2

      chunk:add_row({ 10, 20 })
      chunk:add_row({ 30, 40 })
      chunk:add_row({ 50, 60 }) -- Should trigger growth

      assert.equals(3, chunk:row_count())
      assert.equals(50, chunk:get_width(2, 0))
    end)
  end)
end)
