local ffi = require("ffi")

local M = {}

--- string buffer size
M._str_buf_size = 8192

--- string buffer (module-local reusable buffer)
M._str_buf = ffi.new("char[?]", M._str_buf_size + 1)

--- Ensure buffer
---@param len integer
local function ensure_buffer(len)
  if len >= M._str_buf_size then
    local new_size = math.max(M._str_buf_size * 2, len + 1)
    M._str_buf = ffi.new("char[?]", new_size)
    M._str_buf_size = new_size
  end
end

--- Copy string to C buffer
---@param text string
---@param offset integer 0-based
---@param endpos integer 1-based
---@return integer len
---@return ffi.cdata* char_ptr
local function to_char_array(text, offset, endpos)
  local len = endpos - offset
  if len <= 0 then
    M._str_buf[0] = 0 ---@diagnostic disable-line: no-unknown
    return 0, M._str_buf
  end

  ensure_buffer(len)

  local text_ptr = ffi.cast("const char*", text)
  ffi.copy(M._str_buf, text_ptr + offset, len)
  M._str_buf[len] = 0 ---@diagnostic disable-line: no-unknown

  return len, M._str_buf
end

M.display_width = (function()
  ---@param line string full line text
  ---@param offset? integer 0-based start position of the text
  ---@param endpos? integer end position (1-based, inclusive)
  ---@return integer display_width
  local function fallback(line, offset, endpos)
    offset = offset or 0
    local str = string.sub(line, offset + 1, endpos)
    return vim.fn.strdisplaywidth(str, offset)
  end

  -- NOTE: `linetabsize_col` is an INTERNAL Neovim function.
  -- `nvim_strwidth` API exists but does not handle tab expansion relative to startcol.
  local cdef = [[
    typedef unsigned char char_u;
    int linetabsize_col(int startcol, char_u *s); 
  ]]
  local cdef_ok = pcall(ffi.cdef, cdef)
  if not cdef_ok then
    return fallback
  end

  ---@param line string full line text
  ---@param offset? integer 0-based start position of the text
  ---@param endpos? integer end position (1-based, inclusive)
  ---@return integer display_width
  local function ffi_func(line, offset, endpos)
    offset = offset or 0
    endpos = endpos or #line
    local _, text = to_char_array(line, offset, endpos)
    return ffi.C.linetabsize_col(offset, text) - offset
  end

  -- Try to execute (Check if symbol exists in current binary)
  local run_ok = pcall(ffi_func, "abc", 0, 3)
  if not run_ok then
    return fallback
  end

  return ffi_func
end)()

M.is_number = (function()
  local byte = string.byte

  -- Constants
  local B_0, B_9 = byte("0"), byte("9")
  local B_plus, B_minus = byte("+"), byte("-")
  local B_dot = byte(".")
  local B_comma = byte(",")
  local B_e, B_E = byte("e"), byte("E")
  local B_space, B_tab = byte(" "), byte("\t")

  --- Check string is number
  ---@param line string full line text
  ---@param offset? integer 0-based start position of the text
  ---@param endpos? integer end position (1-based, inclusive)
  ---@return boolean is_number
  return function(line, offset, endpos)
    offset = offset or 0
    endpos = endpos or #line

    local i = offset + 1

    -- Skip leading whitespace
    while i <= endpos do
      local b = byte(line, i)
      if b ~= B_space and b ~= B_tab then
        break
      end
      i = i + 1
    end

    if i > endpos then
      -- Empty or all whitespace
      return false
    end

    -- Check Sign
    local b = byte(line, i)
    if b == B_plus or b == B_minus then
      i = i + 1
      if i > endpos then
        -- Only sign
        return false
      end
      b = byte(line, i)
    end

    -- Check Digits (Integer part) and Dot
    local has_digits = false

    -- Check integer part
    while i <= endpos do
      if b >= B_0 and b <= B_9 then
        has_digits = true
        i = i + 1
      elseif b == B_comma then
        -- "1,234,567" is valid
        i = i + 1
      else
        break
      end

      if i <= endpos then
        b = byte(line, i)
      end
    end

    -- Check Dot and Fractional digits
    if i <= endpos and b == B_dot then
      i = i + 1
      -- Fractional part
      while i <= endpos do
        b = byte(line, i)
        if b >= B_0 and b <= B_9 then
          has_digits = true
          i = i + 1
        else
          break
        end
      end
    end

    if not has_digits then
      -- only ".", "+.", "-." are invalid
      return false
    end

    -- Check Exponent (e/E)
    if i <= endpos and (b == B_e or b == B_E) then
      i = i + 1
      if i > endpos then
        -- "123e" invalid
        return false
      end

      b = byte(line, i)
      -- Exponent sign
      if b == B_plus or b == B_minus then
        i = i + 1
        if i > endpos then
          -- "123e+" invalid
          return false
        end
        b = byte(line, i)
      end

      -- Exponent digits (at least one required)
      local has_exp_digits = false
      while i <= endpos do
        if b >= B_0 and b <= B_9 then
          has_exp_digits = true
          i = i + 1
          if i > endpos then
            break
          end
          b = byte(line, i)
        else
          break
        end
      end
      if not has_exp_digits then
        return false
      end
    end

    -- Skip trailing whitespace
    while i <= endpos do
      if b ~= B_space and b ~= B_tab then
        return false -- Garbage at the end (e.g. "123abc")
      end
      i = i + 1
      if i <= endpos then
        b = byte(line, i)
      end
    end

    return true
  end
end)()

return M
