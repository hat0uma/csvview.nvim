--- Command-line parser for handling key=value style options.
--- This class provides parsing and completion for command-line options.
--- For example:
---   `:Csvview delimiter=, comment=# another=escaped\ space\ value`
---
--- @class Csvview.Cmdline
--- @field vars Csvview.Cmdline.Var[]
local Cmdline = {}

---@alias Csvview.Cmdline.VarSetter fun(options: table, value: string)

---@class Csvview.Cmdline.Var
---@field name string The name of the option
---@field set Csvview.Cmdline.VarSetter A function to set the option value
---@field candidates string[]? A list of completion candidates

--- Create a new instance of Cmdline
--- @param vars Csvview.Cmdline.Var[]? A list of option variables
--- @return Csvview.Cmdline
function Cmdline:new(vars)
  local o = {}
  o.vars = vars or {}

  setmetatable(o, self)
  self.__index = self
  return o
end

--- Add a new option variable to the parser
--- @param name string The name of the option
--- @param set Csvview.Cmdline.VarSetter A function to set the option value
--- @param candidates string[]? A list of completion candidates
function Cmdline:add_var(name, set, candidates)
  table.insert(self.vars, { name = name, set = set, candidates = candidates })
end

--- Parse command-line arguments and set the options
---@param args string The command-line arguments to parse.
---@param options table? default option table to set the parsed values
---@return table
function Cmdline:parse(args, options)
  -- parse key=value pairs
  local parsed_options = self:_parse_kvp(args)

  -- set the options
  options = options or {}
  for _, var in ipairs(self.vars) do
    for _, parsed in ipairs(parsed_options) do
      if parsed.key == var.name then
        local value = self:_unescape(parsed.value)
        var.set(options, value)
      end
    end
  end

  return options
end

--- Parse key=value pairs from the command-line arguments
--- @param args string The command-line arguments to parse.
--- @return {key: string, value: string}[]
function Cmdline:_parse_kvp(args)
  local P = vim.lpeg.P
  local Cg = vim.lpeg.Cg
  local Ct = vim.lpeg.Ct
  local space = P(" ")
  local escaped_space = P("\\ ")
  local kv_sep = P("=")

  -- define key=value pair
  local key = Cg((1 - (space + kv_sep)) ^ 1, "key")
  local value = Cg((escaped_space + (1 - space)) ^ 1, "value")
  local pair = Ct(key * kv_sep * value)
  local pattern = Ct(pair * (space * pair) ^ 0)

  return pattern:match(args) or {}
end

--- unescape delimiter
---@param value string
---@return string
function Cmdline:_unescape(value)
  return (
    value
      :gsub("\\t", "\t") -- tab
      :gsub("\\ ", " ") -- space
  )
end

--- Complete options for CsvView commands
---@param arg_lead string
---@param cmd_line string
---@param cursor_pos integer
---@return string[]
function Cmdline:complete(arg_lead, cmd_line, cursor_pos)
  -- print(arg_lead, cmd_line, cursor_pos)

  --- Check if the command line already has the key
  ---@param key string
  ---@return boolean
  local function already_has_opts(key)
    return string.find(cmd_line, key, 1, true) ~= nil and not vim.endswith(cmd_line, key)
  end

  --- Filter and format the options for completion
  return vim
    .iter(self.vars)
    :filter(
      ---@param v Csvview.Cmdline.Var
      ---@return boolean
      function(v)
        return vim.startswith(v.name, arg_lead) and not already_has_opts(v.name)
      end
    )
    :fold(
      {},
      ---@param acc string[]
      ---@param v Csvview.Cmdline.Var
      ---@return string[]
      function(acc, v)
        -- format the options as key=candidate
        -- e.g. option1 has no candidates, option2 has "candidate1" and "candidate2"
        -- completion will return:
        -- {
        --   "option1=",
        --   "option2=candidate1",
        --   "option2=candidate2",
        -- }
        if not v.candidates or #v.candidates == 0 then
          table.insert(acc, v.name .. "=")
          return acc
        end

        for _, candidate in ipairs(v.candidates or {}) do
          table.insert(acc, v.name .. "=" .. candidate)
        end
        return acc
      end
    )
end

return Cmdline
