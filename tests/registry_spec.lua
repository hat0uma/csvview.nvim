local registry_mod = require("csvview.registry")
local chunk_mod = require("csvview.chunk")
local Registry = registry_mod.Registry
local STATE_IN_QUOTE = chunk_mod.STATE_IN_QUOTE
local STATE_NORMAL = chunk_mod.STATE_NORMAL

describe("Registry", function()
  describe("initialization", function()
    it("creates a new registry", function()
      local registry = Registry:new()
      assert.equals(0, registry:chunk_count())
      assert.equals(0, registry:physical_row_count())
      assert.equals(0, registry:logical_row_count())
    end)

    it("creates a registry with custom max_lookahead", function()
      local registry = Registry:new(50)
      assert.is_not_nil(registry)
    end)
  end)

  describe("insert_row", function()
    it("inserts a row into an empty registry", function()
      local registry = Registry:new()
      registry:insert_row(1, { 10, 20, 30 })

      assert.equals(1, registry:chunk_count())
      assert.equals(1, registry:physical_row_count())
      assert.equals(1, registry:logical_row_count())
    end)

    it("inserts multiple rows", function()
      local registry = Registry:new()
      registry:insert_row(1, { 10, 20, 30 })
      registry:insert_row(2, { 15, 25, 35 })
      registry:insert_row(3, { 5, 10, 15 })

      assert.equals(1, registry:chunk_count())
      assert.equals(3, registry:physical_row_count())
      assert.equals(3, registry:logical_row_count())
    end)

    it("inserts rows with IN_QUOTE state", function()
      local registry = Registry:new()
      registry:insert_row(1, { 10, 20 }, STATE_NORMAL)
      registry:insert_row(2, { 15, 25 }, STATE_IN_QUOTE)
      registry:insert_row(3, { 5, 10 }, STATE_NORMAL)

      assert.equals(3, registry:physical_row_count())
      assert.equals(2, registry:logical_row_count()) -- Only NORMAL rows count as logical rows
    end)
  end)

  describe("remove_row", function()
    it("removes a row", function()
      local registry = Registry:new()
      registry:insert_row(1, { 10, 20 })
      registry:insert_row(2, { 30, 40 })
      registry:insert_row(3, { 50, 60 })

      registry:remove_row(2)

      assert.equals(2, registry:physical_row_count())
      assert.equals(2, registry:logical_row_count())
    end)

    it("removes the last row and deletes empty chunk", function()
      local registry = Registry:new()
      registry:insert_row(1, { 10, 20 })

      registry:remove_row(1)

      assert.equals(0, registry:chunk_count())
      assert.equals(0, registry:physical_row_count())
    end)
  end)

  describe("update_row", function()
    it("updates an existing row", function()
      local registry = Registry:new()
      registry:insert_row(1, { 10, 20 })
      registry:insert_row(2, { 30, 40 })

      registry:update_row(1, { 100, 200 })

      assert.equals(100, registry:get_global_max_width(0))
      assert.equals(200, registry:get_global_max_width(1))
    end)

    it("updates row state", function()
      local registry = Registry:new()
      registry:insert_row(1, { 10, 20 }, STATE_NORMAL)
      registry:insert_row(2, { 30, 40 }, STATE_NORMAL)

      assert.equals(2, registry:logical_row_count())

      registry:update_row(1, { 10, 20 }, STATE_IN_QUOTE)

      assert.equals(1, registry:logical_row_count())
    end)
  end)

  describe("global max width", function()
    it("calculates global max width across chunks", function()
      local registry = Registry:new()
      registry:insert_row(1, { 10, 20, 30 })
      registry:insert_row(2, { 15, 100, 35 })
      registry:insert_row(3, { 5, 50, 40 })

      assert.equals(15, registry:get_global_max_width(0))
      assert.equals(100, registry:get_global_max_width(1))
      assert.equals(40, registry:get_global_max_width(2))
    end)

    it("updates global max width on row insertion", function()
      local registry = Registry:new()
      registry:insert_row(1, { 10, 20 })

      assert.equals(10, registry:get_global_max_width(0))

      registry:insert_row(2, { 100, 30 })

      assert.equals(100, registry:get_global_max_width(0))
    end)

    it("recalculates global max width on row removal", function()
      local registry = Registry:new()
      registry:insert_row(1, { 100, 20 })
      registry:insert_row(2, { 50, 30 })

      assert.equals(100, registry:get_global_max_width(0))

      registry:remove_row(1)

      assert.equals(50, registry:get_global_max_width(0))
    end)
  end)

  describe("physical to logical conversion", function()
    it("converts physical line to logical row for single-line rows", function()
      local registry = Registry:new()
      registry:insert_row(1, { 10, 20 }, STATE_NORMAL)
      registry:insert_row(2, { 30, 40 }, STATE_NORMAL)
      registry:insert_row(3, { 50, 60 }, STATE_NORMAL)

      assert.equals(1, registry:physical_to_logical(1))
      assert.equals(2, registry:physical_to_logical(2))
      assert.equals(3, registry:physical_to_logical(3))
    end)

    it("converts physical line to logical row for multi-line rows", function()
      local registry = Registry:new()
      registry:insert_row(1, { 10, 20 }, STATE_IN_QUOTE)
      registry:insert_row(2, { 30, 40 }, STATE_NORMAL)
      registry:insert_row(3, { 50, 60 }, STATE_NORMAL)

      -- Physical line 1 is IN_QUOTE (not a logical row start)
      -- Physical line 2 is NORMAL (logical row 1)
      assert.equals(1, registry:physical_to_logical(2))
      assert.equals(2, registry:physical_to_logical(3))
    end)
  end)

  describe("logical to physical conversion", function()
    it("converts logical row to physical line for single-line rows", function()
      local registry = Registry:new()
      registry:insert_row(1, { 10, 20 }, STATE_NORMAL)
      registry:insert_row(2, { 30, 40 }, STATE_NORMAL)
      registry:insert_row(3, { 50, 60 }, STATE_NORMAL)

      assert.equals(1, registry:logical_to_physical(1))
      assert.equals(2, registry:logical_to_physical(2))
      assert.equals(3, registry:logical_to_physical(3))
    end)

    it("converts logical row to physical line for multi-line rows", function()
      local registry = Registry:new()
      registry:insert_row(1, { 10, 20 }, STATE_IN_QUOTE)
      registry:insert_row(2, { 30, 40 }, STATE_IN_QUOTE)
      registry:insert_row(3, { 50, 60 }, STATE_NORMAL)
      registry:insert_row(4, { 70, 80 }, STATE_NORMAL)

      -- Logical row 1 starts at physical line 1 (IN_QUOTE continues through line 3)
      -- Logical row 2 starts at physical line 4
      assert.equals(1, registry:logical_to_physical(1))
      assert.equals(4, registry:logical_to_physical(2))
    end)
  end)

  describe("get_logical_row_range", function()
    it("returns range for single-line row", function()
      local registry = Registry:new()
      registry:insert_row(1, { 10, 20 }, STATE_NORMAL)
      registry:insert_row(2, { 30, 40 }, STATE_NORMAL)

      local start_phys, end_phys = registry:get_logical_row_range(1)
      assert.equals(1, start_phys)
      assert.equals(1, end_phys)
    end)

    it("returns range for multi-line row", function()
      local registry = Registry:new()
      registry:insert_row(1, { 10, 20 }, STATE_IN_QUOTE)
      registry:insert_row(2, { 30, 40 }, STATE_IN_QUOTE)
      registry:insert_row(3, { 50, 60 }, STATE_NORMAL)
      registry:insert_row(4, { 70, 80 }, STATE_NORMAL)

      -- Logical row 1 spans physical lines 1-3
      local start_phys, end_phys = registry:get_logical_row_range(1)
      assert.equals(1, start_phys)
      assert.equals(3, end_phys)

      -- Logical row 2 is a single line
      start_phys, end_phys = registry:get_logical_row_range(2)
      assert.equals(4, start_phys)
      assert.equals(4, end_phys)
    end)
  end)

  describe("chunk splitting and merging", function()
    it("splits chunks when they grow too large", function()
      local registry = Registry:new()

      -- Insert more than SPLIT_THRESHOLD (200) rows
      for i = 1, 210 do
        registry:insert_row(i, { i, i * 2 })
      end

      -- Should have split into multiple chunks
      assert.is_true(registry:chunk_count() > 1)
      assert.equals(210, registry:physical_row_count())
    end)

    it("merges chunks when they shrink too small", function()
      local registry = Registry:new()

      -- Insert enough rows to cause a split
      for i = 1, 210 do
        registry:insert_row(i, { i, i * 2 })
      end

      local initial_chunk_count = registry:chunk_count()

      -- Remove many rows to trigger merging
      for i = 210, 100, -1 do
        registry:remove_row(i)
      end

      -- Should have merged chunks
      assert.is_true(registry:chunk_count() <= initial_chunk_count)
      assert.equals(99, registry:physical_row_count())
    end)
  end)

  describe("circuit breaker", function()
    it("prevents infinite IN_QUOTE propagation", function()
      local registry = Registry:new(10) -- max_lookahead = 10

      -- Insert more than 10 consecutive IN_QUOTE rows
      for i = 1, 15 do
        registry:insert_row(i, { 10, 20 }, STATE_IN_QUOTE)
      end

      -- Apply circuit breaker
      registry:apply_circuit_breaker()

      -- Some IN_QUOTE states should have been reset to NORMAL
      assert.is_true(registry:logical_row_count() > 0)
    end)
  end)

  describe("clear", function()
    it("clears all chunks and data", function()
      local registry = Registry:new()
      registry:insert_row(1, { 10, 20 })
      registry:insert_row(2, { 30, 40 })

      registry:clear()

      assert.equals(0, registry:chunk_count())
      assert.equals(0, registry:physical_row_count())
      assert.equals(0, registry:logical_row_count())
    end)
  end)
end)
