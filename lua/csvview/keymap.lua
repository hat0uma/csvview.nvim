local M = {}

---@class CsvView.Keymap: vim.keymap.set.Opts
---@field [1] string key
---@field [2]? string | fun()
---@field mode string | string[]

---@class CsvView.Action: vim.keymap.set.Opts
---@field [1]? string | fun()

---Pop key from table
---@param tbl table<any,any>
---@param key any
---@return any
local function pop(tbl, key)
  local value = tbl[key]
  tbl[key] = nil
  return value
end

---Register keymaps for csvview
---@param opts CsvView.Options
function M.register(opts)
  local default_map_opts = { buffer = true }
  local keymaps = vim.deepcopy(opts.keymaps) ---@type table<string|integer, CsvView.Keymap>
  local actions = vim.deepcopy(opts.actions)
  for idx, map in pairs(keymaps) do
    if type(idx) == "string" then
      -- Example:
      -- keymaps = {
      --   test = { "<leader>h", mode = "n", silent = true },
      -- }
      -- actions = {
      --   test = { function() print("hello") end, desc = "print hello" },
      -- }
      local action = actions[idx]
      if action then
        action = vim.deepcopy(action)
        local lhs = pop(map, 1)
        local rhs = pop(action, 1)
        local mode = pop(map, "mode")
        local map_opts = vim.tbl_extend("keep", map, action, default_map_opts)
        vim.keymap.set(mode, lhs, rhs, map_opts)
      else
        vim.notify(string.format("csvview: preset not found for %s", idx))
      end
    elseif type(idx) == "number" then
      -- Example:
      -- keymaps = {
      --   ...
      --   { "<leader>h", function() print("hello") end, mode = "n" , buffer = true },
      -- }
      local lhs = pop(map, 1)
      local rhs = pop(map, 2)
      local mode = pop(map, "mode")
      local map_opts = vim.tbl_extend("keep", map, default_map_opts)
      if rhs then
        vim.keymap.set(mode, lhs, rhs, map_opts)
      else
        vim.notify(string.format("csvview: rhs not found for %s", lhs))
      end
    end
  end
end

--- Unregister keymaps for csvview
---@param opts CsvView.Options
function M.unregister(opts)
  local keymaps = opts.keymaps ---@type table<string|integer, CsvView.Keymap>
  for _, map in pairs(keymaps) do
    local lhs = map[1]
    local mode = map.mode
    vim.keymap.del(mode, lhs, { buffer = true })
  end
end

return M
