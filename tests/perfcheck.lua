-- perfcheck.lua
-- Usage:
--   nvim --headless --clean -c "luafile tests/perfcheck.lua" -c "qa!"
--   PERFCHECK_LINES=100000 PERFCHECK_COLS=20 nvim --headless --clean -c "luafile tests/perfcheck.lua" -c "qa!"
--   PERFCHECK_JSON=result.json nvim --headless --clean -c "luafile tests/perfcheck.lua" -c "qa!"
--
-- Environment variables:
--   PERFCHECK_COLD_ITERS  cold runs (one fresh nvim each)     (default: 5)
--   PERFCHECK_ITERS       warm runs (same process)            (default: 10)
--   PERFCHECK_WARMUP      warmup iterations before warm runs  (default: 3)
--   PERFCHECK_MEM_ITERS   memory iterations (GC stopped)      (default: 3)
--   PERFCHECK_LINES       data rows (excluding header)        (default: 100000)
--   PERFCHECK_COLS        columns                             (default: 15)
--   PERFCHECK_SCROLLS     scroll redraws measured per run     (default: 20)
--   PERFCHECK_WIN_LINES   screen lines                        (default: 50)
--   PERFCHECK_WIN_COLS    screen columns                      (default: 200)
--   PERFCHECK_CHUNKSIZE   parser.async_chunksize              (default: plugin default)
--   PERFCHECK_TIMEOUT     timeout per iteration in ms         (default: 60000)
--   PERFCHECK_JSON        write results as JSON to this path  (optional)
--
-- What is measured:
--   Timing runs (GC running normally, as in real use).
--   They are taken in two settings, because LuaJIT trace state makes them differ significantly:
--     cold : the first enable() in a fresh nvim process (each sample is a separate child process)
--     warm : repeated enable() in the same process, after warmup
--   Metrics:
--     parse   : enable() -> metrics computation finished (async chunked parsing)
--     attach  : metrics finished -> CsvViewAttach (view attach + first render of the visible window)
--     total   : enable() -> CsvViewAttach (wall clock), and the CPU time of the same span
--     scroll  : one `redraw` after jumping to an unrendered position of the file
--   Memory runs (GC stopped while enabling, so numbers are deterministic):
--     alloc    : Lua heap allocated during enable() -> CsvViewAttach
--     resident : Lua heap still referenced while attached (after full GC)
--     leak     : Lua heap left after disable() and buffer deletion (after full GC)
--
-- Exits with a non-zero status if any iteration fails or times out.

local uv = vim.uv or vim.loop

-----------------------------------------------------
-- Make sure the plugin under test is the one in this repository.
local script_path = debug.getinfo(1, "S").source:sub(2)
local repo_root = vim.fn.fnamemodify(script_path, ":p:h:h")
vim.opt.runtimepath:prepend(repo_root)
for name in pairs(package.loaded) do
  if name == "csvview" or vim.startswith(name, "csvview.") then
    package.loaded[name] = nil
  end
end

---Helper to get config from env or default
---@param name string
---@param default integer?
---@return integer
local function get_env_num(name, default)
  local val = tonumber(os.getenv(name))
  return val or default
end

local cfg = {
  cold_iterations = get_env_num("PERFCHECK_COLD_ITERS", 5),
  iterations = get_env_num("PERFCHECK_ITERS", 10),
  warmup = get_env_num("PERFCHECK_WARMUP", 3),
  mem_iterations = get_env_num("PERFCHECK_MEM_ITERS", 3),
  lines = get_env_num("PERFCHECK_LINES", 100000),
  columns = get_env_num("PERFCHECK_COLS", 15),
  scrolls = get_env_num("PERFCHECK_SCROLLS", 20),
  win_lines = get_env_num("PERFCHECK_WIN_LINES", 50),
  win_cols = get_env_num("PERFCHECK_WIN_COLS", 200),
  timeout = get_env_num("PERFCHECK_TIMEOUT", 60000),
  json = os.getenv("PERFCHECK_JSON"),
  opts = { --- @type CsvView.Options
    parser = {
      async_chunksize = get_env_num("PERFCHECK_CHUNKSIZE", nil),
    },
  },
}

--- log
---@param fmt string
---@param ... any
local function log(fmt, ...)
  print(string.format("[PERFCHECK] " .. fmt .. "\n", ...))
end

---Generate CSV lines in memory
---@return string[]
local function generate_lines()
  local lines = {} --- @type string[]

  -- Header
  local headers = {} --- @type string[]
  for c = 1, cfg.columns do
    headers[c] = "Col_" .. c
  end
  lines[1] = table.concat(headers, ",")

  -- Rows
  local row = {} --- @type string[]
  for r = 1, cfg.lines do
    for c = 1, cfg.columns do
      local m = c % 5
      if m == 1 then
        row[c] = string.format('"Q %d-%d"', r, c)
      elseif m == 2 then
        row[c] = "日本語" .. r
      elseif m == 3 then
        row[c] = ""
      elseif m == 4 then
        row[c] = "Long_payload_" .. r
      else
        row[c] = tostring(r * c)
      end
    end
    lines[r + 1] = table.concat(row, ",")
  end
  return lines
end

---@class PerfCheck.Stats
---@field median number
---@field min number
---@field p95 number
---@field max number
---@field avg number
---@field std_dev number

---Calculate standard statistics
---@param samples number[]
---@return PerfCheck.Stats
local function calculate_stats(samples)
  local n = #samples
  if n == 0 then
    return { median = 0, min = 0, p95 = 0, max = 0, avg = 0, std_dev = 0 }
  end

  local sorted = vim.deepcopy(samples)
  table.sort(sorted)

  local sum = 0
  for _, v in ipairs(sorted) do
    sum = sum + v
  end
  local avg = sum / n

  local sq_sum = 0
  for _, v in ipairs(sorted) do
    sq_sum = sq_sum + (v - avg) ^ 2
  end

  ---@param p number percentile in [0, 1]
  local function percentile(p)
    -- linear interpolation between closest ranks
    local pos = 1 + (n - 1) * p
    local lo = math.floor(pos)
    local hi = math.min(lo + 1, n)
    return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo)
  end

  return {
    median = percentile(0.5),
    min = sorted[1],
    p95 = percentile(0.95),
    max = sorted[n],
    avg = avg,
    std_dev = n > 1 and math.sqrt(sq_sum / (n - 1)) or 0, -- sample standard deviation
  }
end

local function full_gc()
  collectgarbage("collect")
  collectgarbage("collect")
end

---Let pending `vim.schedule` callbacks (e.g. overlay window cleanup) run.
local function flush_scheduled()
  vim.wait(20, function()
    return false
  end)
end

-----------------------------------------------------
-- Instrumentation
--
-- Timestamps are taken inside the callbacks themselves, so that the polling latency
-- of `vim.wait` is not included in the measurement.

local probe = {
  buf = nil, ---@type integer?
  parse_done = nil, ---@type integer?
  attached = nil, ---@type integer?
  attached_cpu = nil, ---@type number?
  err = nil, ---@type string?
}

local function reset_probe(buf)
  probe.buf = buf
  probe.parse_done = nil
  probe.attached = nil
  probe.attached_cpu = nil
  probe.err = nil
end

require("csvview")
local CsvViewMetrics = require("csvview.metrics")
local orig_compute_buffer = CsvViewMetrics.compute_buffer
---@diagnostic disable-next-line: duplicate-set-field
CsvViewMetrics.compute_buffer = function(self, on_end)
  return orig_compute_buffer(self, function(err)
    if self._bufnr == probe.buf then
      probe.parse_done = probe.parse_done or uv.hrtime()
    end
    if on_end then
      return on_end(err)
    end
  end)
end

local probe_augroup = vim.api.nvim_create_augroup("csvview_perfcheck", {})
vim.api.nvim_create_autocmd("User", {
  group = probe_augroup,
  pattern = "CsvViewAttach",
  callback = function(args)
    if args.data == probe.buf then
      probe.attached = uv.hrtime()
      probe.attached_cpu = os.clock()
    end
  end,
})

-- csvview reports async failures via vim.notify; capture them so we fail fast instead of timing out.
local orig_notify = vim.notify
---@diagnostic disable-next-line: duplicate-set-field
vim.notify = function(msg, level, ...)
  if level == vim.log.levels.ERROR then
    probe.err = msg
  end
  return orig_notify(msg, level, ...)
end

local function restore_instrumentation()
  CsvViewMetrics.compute_buffer = orig_compute_buffer
  vim.notify = orig_notify
  pcall(vim.api.nvim_del_augroup_by_id, probe_augroup)
end

-----------------------------------------------------
-- Benchmark

---Create a buffer with the data and show it in the current window (so that rendering is exercised).
---@param lines string[]
---@return integer
local function setup_buffer(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.cmd("redraw")
  return buf
end

---@param buf integer
local function teardown_buffer(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  if require("csvview").is_enabled(buf) then
    pcall(require("csvview").disable, buf)
  end
  pcall(vim.api.nvim_buf_delete, buf, { force = true })
  flush_scheduled()
end

---Enable csvview and wait for CsvViewAttach.
---@param buf integer
---@return string? err
local function enable_and_wait(buf)
  require("csvview").enable(buf, cfg.opts)
  local ok = vim.wait(cfg.timeout, function()
    return probe.attached ~= nil or probe.err ~= nil
  end, 1)
  if probe.err then
    return probe.err
  elseif not ok then
    return string.format("timeout after %d ms", cfg.timeout)
  end
end

---Measure redraw time after jumping to positions that have not been rendered yet.
---@param buf integer
---@return number[] samples_ms
local function measure_scroll(buf)
  local samples = {} ---@type number[]
  local line_count = vim.api.nvim_buf_line_count(buf)
  for k = 1, cfg.scrolls do
    local lnum = math.max(1, math.floor(k * line_count / (cfg.scrolls + 1)))
    vim.fn.winrestview({ topline = lnum, lnum = lnum, col = 0 })
    local t = uv.hrtime()
    vim.cmd("redraw")
    table.insert(samples, (uv.hrtime() - t) / 1e6)
  end
  return samples
end

---@class PerfCheck.TimingSample
---@field total_ms number
---@field cpu_ms number
---@field parse_ms number
---@field attach_ms number
---@field scroll_ms number median of scroll redraws in this run

---@param lines string[]
---@return PerfCheck.TimingSample? sample
---@return string? err
local function run_timing(lines)
  local buf = setup_buffer(lines)
  reset_probe(buf)

  local ok, res = pcall(function()
    full_gc()
    local start_cpu = os.clock()
    local start_time = uv.hrtime()

    local err = enable_and_wait(buf)
    if err then
      return err
    end

    local scroll = calculate_stats(measure_scroll(buf))
    return {
      total_ms = (probe.attached - start_time) / 1e6,
      cpu_ms = (probe.attached_cpu - start_cpu) * 1000,
      parse_ms = (probe.parse_done - start_time) / 1e6,
      attach_ms = (probe.attached - probe.parse_done) / 1e6,
      scroll_ms = scroll.median,
    }
  end)
  teardown_buffer(buf)

  if not ok then
    return nil, tostring(res)
  elseif type(res) == "string" then
    return nil, res
  end
  return res
end

---@class PerfCheck.MemorySample
---@field alloc_kb number
---@field resident_kb number
---@field leak_kb number

---@param lines string[]
---@return PerfCheck.MemorySample? sample
---@return string? err
local function run_memory(lines)
  local buf = setup_buffer(lines)
  reset_probe(buf)

  local ok, res = pcall(function()
    full_gc()
    local base = collectgarbage("count")

    collectgarbage("stop")
    local err = enable_and_wait(buf)
    local alloc = collectgarbage("count") - base
    collectgarbage("restart")
    if err then
      return err
    end

    full_gc()
    local resident = collectgarbage("count") - base

    require("csvview").disable(buf)
    vim.api.nvim_buf_delete(buf, { force = true })
    flush_scheduled()
    full_gc()
    local leak = collectgarbage("count") - base

    return { alloc_kb = alloc, resident_kb = resident, leak_kb = leak }
  end)
  collectgarbage("restart")
  teardown_buffer(buf)

  if not ok then
    return nil, tostring(res)
  elseif type(res) == "string" then
    return nil, res
  end
  return res
end

---@param path string
---@param data table
local function write_json(path, data)
  local f, err = io.open(path, "w")
  if not f then
    log("Could not write JSON to %s: %s", path, err)
    return
  end
  f:write(vim.json.encode(data))
  f:close()
  log("Wrote results to %s", path)
end

---@param samples table[]
---@param key string
---@return PerfCheck.Stats
local function stats_of(samples, key)
  return calculate_stats(vim.tbl_map(function(s)
    return s[key]
  end, samples))
end

local CHILD_RESULT_PREFIX = "PERFCHECK_CHILD_RESULT:"

---Child process mode: run a single cold timing run and report it on stdout.
---@return boolean success
local function run_child()
  vim.o.lines = cfg.win_lines
  vim.o.columns = cfg.win_cols
  local s, err = run_timing(generate_lines())
  io.write(CHILD_RESULT_PREFIX .. vim.json.encode({ sample = s, error = err }) .. "\n")
  io.flush()
  return s ~= nil
end

---Run one cold timing sample in a fresh nvim process.
---@return PerfCheck.TimingSample? sample
---@return string? err
local function run_cold()
  local res = vim
    .system({ vim.v.progpath, "--headless", "--clean", "-c", "luafile " .. script_path, "-c", "qa!" }, {
      env = { PERFCHECK_CHILD = "1" },
      text = true,
    })
    :wait(cfg.timeout + 30000)
  for line in vim.gsplit(res.stdout or "", "\n", { plain = true }) do
    if vim.startswith(line, CHILD_RESULT_PREFIX) then
      local decoded = vim.json.decode(line:sub(#CHILD_RESULT_PREFIX + 1))
      return decoded.sample, decoded.error
    end
  end
  return nil, string.format("child exited with %d: %s", res.code, vim.trim(res.stderr or ""))
end

---@param label string
---@param s PerfCheck.TimingSample
local function log_timing(label, s)
  log(
    "[%s] total %.2f ms (cpu %.2f) | parse %.2f | attach %.2f | scroll %.3f ms",
    label,
    s.total_ms,
    s.cpu_ms,
    s.parse_ms,
    s.attach_ms,
    s.scroll_ms
  )
end

---@return boolean success
local function run_perfcheck()
  vim.o.lines = cfg.win_lines
  vim.o.columns = cfg.win_cols

  log("Configuration: %s", vim.inspect(cfg))
  log("Plugin under test: %s", vim.api.nvim_get_runtime_file("lua/csvview/init.lua", false)[1])
  log("%s | %s", vim.version and tostring(vim.version()) or "?", jit and jit.version or _VERSION)
  if vim.env.MYVIMRC and vim.env.MYVIMRC ~= "" then
    log("WARNING: user config is loaded (%s). Run with --clean for reliable results.", vim.env.MYVIMRC)
  end

  local t_gen_start = uv.hrtime()
  local lines = generate_lines()
  log("Generated %d lines, %d cols in %.2f ms", cfg.lines, cfg.columns, (uv.hrtime() - t_gen_start) / 1e6)

  local failure ---@type string?

  -----------------------------------------------------
  -- Cold timing
  log("Starting cold runs (fresh process each)...")
  local colds = {} ---@type PerfCheck.TimingSample[]
  for i = 1, cfg.cold_iterations do
    local s, err = run_cold()
    if not s then
      failure = string.format("cold iteration %d failed: %s", i, err)
      break
    end
    log_timing(string.format("Cold %02d", i), s)
    table.insert(colds, s)
  end

  -----------------------------------------------------
  -- Warm timing
  local timings = {} ---@type PerfCheck.TimingSample[]
  if not failure then
    log("Starting warm runs (same process)...")
  end
  for i = 1, failure and 0 or (cfg.warmup + cfg.iterations) do
    local s, err = run_timing(lines)
    if not s then
      failure = string.format("timing iteration %d failed: %s", i, err)
      break
    end
    log_timing(i <= cfg.warmup and string.format("Warmup %d", i) or string.format("Warm %02d", i - cfg.warmup), s)
    if i > cfg.warmup then
      table.insert(timings, s)
    end
  end

  -----------------------------------------------------
  -- Memory
  local memories = {} ---@type PerfCheck.MemorySample[]
  if not failure then
    log("Starting memory runs (GC stopped)...")
    for i = 1, cfg.mem_iterations do
      local s, err = run_memory(lines)
      if not s then
        failure = string.format("memory iteration %d failed: %s", i, err)
        break
      end
      log("[Mem %02d] alloc %.0f KB | resident %.0f KB | leak %+.2f KB", i, s.alloc_kb, s.resident_kb, s.leak_kb)
      table.insert(memories, s)
    end
  end

  if failure then
    log("ERROR: %s", failure)
  end

  -----------------------------------------------------
  -- Report
  local cold = {
    total_ms = stats_of(colds, "total_ms"),
    cpu_ms = stats_of(colds, "cpu_ms"),
    parse_ms = stats_of(colds, "parse_ms"),
    attach_ms = stats_of(colds, "attach_ms"),
    scroll_ms = stats_of(colds, "scroll_ms"),
  }
  local result = {
    total_ms = stats_of(timings, "total_ms"),
    cpu_ms = stats_of(timings, "cpu_ms"),
    parse_ms = stats_of(timings, "parse_ms"),
    attach_ms = stats_of(timings, "attach_ms"),
    scroll_ms = stats_of(timings, "scroll_ms"),
    alloc_kb = stats_of(memories, "alloc_kb"),
    resident_kb = stats_of(memories, "resident_kb"),
    leak_kb = stats_of(memories, "leak_kb"),
  }
  ---@param parse PerfCheck.Stats
  local function throughput_of(parse)
    return parse.median > 0 and cfg.lines / (parse.median / 1000) or 0
  end

  local function row(name, s, unit, fmt)
    fmt = fmt or "%10.2f"
    print(
      string.format(
        " %-14s" .. string.rep(" " .. fmt, 5) .. " %s",
        name,
        s.median,
        s.min,
        s.p95,
        s.max,
        s.std_dev,
        unit
      )
    )
  end

  print("")
  print("==========================================================================================")
  print(
    string.format(
      " PERFCHECK RESULTS (Cold N=%d, Warm N=%d, Mem N=%d, Lines=%d, Cols=%d, Screen=%dx%d)",
      #colds,
      #timings,
      #memories,
      cfg.lines,
      cfg.columns,
      cfg.win_cols,
      cfg.win_lines
    )
  )
  print("==========================================================================================")
  print(string.format(" %-14s %10s %10s %10s %10s %10s", "", "median", "min", "p95", "max", "stddev"))
  for _, section in ipairs({ { "Cold", cold }, { "Warm", result } }) do
    local name, r = section[1], section[2]
    print(string.format(" [%s] parse throughput: %.0f lines/sec (at median)", name, throughput_of(r.parse_ms)))
    row("total", r.total_ms, "ms")
    row("  cpu", r.cpu_ms, "ms")
    row("  parse", r.parse_ms, "ms")
    row("  attach", r.attach_ms, "ms")
    row("scroll redraw", r.scroll_ms, "ms", "%10.3f")
  end
  print(" [Memory]")
  row("alloc", result.alloc_kb, "KB", "%10.0f")
  row("resident", result.resident_kb, "KB", "%10.0f")
  row("leak", result.leak_kb, "KB")
  if failure then
    print(" FAILED: " .. failure)
  end
  print("==========================================================================================\n")

  if cfg.json then
    write_json(cfg.json, {
      config = cfg,
      success = failure == nil,
      error = failure,
      cold = cold,
      warm = {
        total_ms = result.total_ms,
        cpu_ms = result.cpu_ms,
        parse_ms = result.parse_ms,
        attach_ms = result.attach_ms,
        scroll_ms = result.scroll_ms,
      },
      memory = { alloc_kb = result.alloc_kb, resident_kb = result.resident_kb, leak_kb = result.leak_kb },
      cold_samples = colds,
      warm_samples = timings,
      memory_samples = memories,
    })
  end

  return failure == nil
end

local ok, result = pcall(os.getenv("PERFCHECK_CHILD") and run_child or run_perfcheck)
restore_instrumentation()
if not ok then
  log("ERROR: %s", result)
end
if not (ok and result) and #vim.api.nvim_list_uis() == 0 then
  -- Signal failure to the shell when running headless.
  vim.cmd("cquit 1")
end
