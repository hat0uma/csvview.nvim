-- perfcheck.lua
-- Usage:
--   nvim --headless -c "luafile tests/perfcheck.lua" -c "qa!"
--   PERFCHECK_LINES=100000 PERFCHECK_COLS=20 nvim --headless -c "luafile tests/perfcheck.lua" -c "qa!"

local uv = vim.uv or vim.loop

---Helper to get config from env or default
---@param name string
---@param default integer
---@return integer
local function get_env_num(name, default)
  local val = tonumber(os.getenv(name))
  return val or default
end

local cfg = {
  iterations = get_env_num("PERFCHECK_ITERS", 10),
  warmup = get_env_num("PERFCHECK_WARMUP", 3),
  lines = get_env_num("PERFCHECK_LINES", 100000),
  columns = get_env_num("PERFCHECK_COLS", 15),
  filename = "perf_gen.csv",
  opts = { --- @type CsvView.Options
    parser = {
      comments = { "#" },
      max_lookahead = 50,
      async_chunksize = 100,
    },
  },
}

--- log
---@param fmt string
---@param ... any
local function log(fmt, ...)
  print(string.format("[PERFCHECK] " .. fmt .. "\n", ...))
end

---Generate CSV File
local function prepare_data_file()
  local f = io.open(cfg.filename, "w")
  if not f then
    error("Could not open file for writing")
  end

  -- Header
  local headers = {} --- @type string[]
  for c = 1, cfg.columns do
    headers[c] = "Col_" .. c
  end
  f:write(table.concat(headers, ",") .. "\n")

  -- Rows
  for r = 1, cfg.lines do
    local row = {} --- @type string[]
    for c = 1, cfg.columns do
      local val --- @type string
      local m = c % 5
      if m == 1 then
        val = string.format('"Q %d-%d"', r, c)
      elseif m == 2 then
        val = "日本語" .. r
      elseif m == 3 then
        val = ""
      elseif m == 4 then
        val = "Long_payload_" .. r
      else
        val = tostring(r * c)
      end
      row[c] = val
    end
    f:write(table.concat(row, ",") .. "\n")
  end
  f:close()
  log("Generated %s (%d lines, %d cols)", cfg.filename, cfg.lines, cfg.columns)
end

---Read file into memory (simulate buffer load)
---@return string[]
local function load_data_file()
  local lines = {}
  for line in io.lines(cfg.filename) do
    table.insert(lines, line)
  end
  return lines
end

---Calculate standard statistics
---@param samples number[]
---@return number avg, integer min, integer max, integer std_dev
local function calculate_stats(samples)
  if #samples == 0 then
    return 0, 0, 0, 0
  end
  local sum = 0
  local min = math.huge
  local max = -math.huge

  for _, v in ipairs(samples) do
    sum = sum + v
    if v < min then
      min = v
    end
    if v > max then
      max = v
    end
  end
  local avg = sum / #samples

  local sq_sum = 0
  for _, v in ipairs(samples) do
    sq_sum = sq_sum + (v - avg) ^ 2
  end
  local std_dev = math.sqrt(sq_sum / #samples)

  return avg, min, max, std_dev
end

local function run_perfcheck()
  log("Configuration: %s", vim.inspect(cfg))

  -----------------------------------------------------
  -- Generate Data
  local t_gen_start = uv.hrtime()
  prepare_data_file()
  local lines = load_data_file()
  local t_gen_end = uv.hrtime()
  log("Data generation took %.2f ms", (t_gen_end - t_gen_start) / 1e6)

  -----------------------------------------------------
  -- perfcheck loop
  log("Starting perfcheck loop...")

  local times = {} ---@type number[]
  local mems_retained = {} ---@type number[]
  local mems_peak = {} ---@type number[]
  local throughputs = {} ---@type number[]

  for i = 1, cfg.warmup + cfg.iterations do
    -- Create Buffer
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    collectgarbage("collect")
    collectgarbage("collect")

    local start_mem = collectgarbage("count") ---@type integer
    local start_time = uv.hrtime()
    local done = false

    -- Setup event listener
    local autocmd_id = vim.api.nvim_create_autocmd("User", {
      pattern = "CsvViewAttach",
      callback = function(args)
        if args.data == buf then
          done = true
        end
      end,
      once = true,
    })

    -- Run Target
    local status, err = pcall(require("csvview").enable, buf, cfg.opts)
    if not status then
      log("Error during enable: %s", err)
      break
    end

    -- Wait for async completion and observe peak.
    local peak_mem = start_mem
    local wait_ok = vim.wait(60000, function()
      local current = collectgarbage("count")
      if current > peak_mem then
        peak_mem = current
      end
      return done
    end, 5)

    if not wait_ok then
      vim.api.nvim_del_autocmd(autocmd_id)
      log("TIMEOUT on iteration %d", i)
      break
    end

    -- Collect data
    local end_time = uv.hrtime()

    -- Cleanup
    require("csvview").disable(buf)
    vim.api.nvim_buf_delete(buf, { force = true })

    collectgarbage("collect")
    collectgarbage("collect")
    local end_mem_retained = collectgarbage("count") ---@type integer

    -- Calculate Metrics
    local duration_ms = (end_time - start_time) / 1e6
    local retained_delta = end_mem_retained - start_mem
    local peak_delta = peak_mem - start_mem
    local lines_per_sec = cfg.lines / (duration_ms / 1000)

    if i <= cfg.warmup then
      log("[Warmup %d] %.2f ms", i, duration_ms)
    else
      local run_idx = i - cfg.warmup
      table.insert(times, duration_ms)
      table.insert(mems_retained, retained_delta)
      table.insert(mems_peak, peak_delta)
      table.insert(throughputs, lines_per_sec)
      log(
        "[Run %02d] Time: %.2f ms | Mem Peak: %+.2f KB | Mem Retained: %+.2f KB | %.0f lines/s",
        run_idx,
        duration_ms,
        peak_delta,
        retained_delta,
        lines_per_sec
      )
    end

    -- Small pause between runs
    uv.sleep(10)
  end

  -- Final Report
  local t_avg, t_min, t_max, t_std = calculate_stats(times)
  local mr_avg, mr_min, mr_max = calculate_stats(mems_retained)
  local mp_avg, mp_min, mp_max = calculate_stats(mems_peak)
  local tp_avg = calculate_stats(throughputs)

  print("\n")
  print("================================================================")
  print(string.format(" PERFCHECK RESULTS (N=%d, Lines=%d, Cols=%d)", #times, cfg.lines, cfg.columns))
  print("================================================================")
  print(string.format(" Execution Time : %.2f ms (±%.2f) [Min: %.2f, Max: %.2f]", t_avg, t_std, t_min, t_max))
  print(string.format(" Throughput     : %.0f lines/sec", tp_avg))
  print(string.format(" Observed Peak  : %.2f KB (Avg) [Min: %.2f, Max: %.2f]", mp_avg, mp_min, mp_max))
  print(string.format(" Retained Mem   : %.2f KB (Avg) [Min: %.2f, Max: %.2f]", mr_avg, mr_min, mr_max))
  print("================================================================")

  -- Cleanup file
  os.remove(cfg.filename)
end

run_perfcheck()
