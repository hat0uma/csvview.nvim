--- Utility functions for CSVView.
local M = {}

---@class CsvView.Cursor
---@field kind "field" | "comment" | "empty_line" Cursor kind
---@field pos [integer,integer?] 1-based [row, col] csv coordinates
---@field anchor? CsvView.CursorAnchor
---@field text? string

--- Cursor anchor states within a CSV field.
--- - `"start"`: Cursor is at the beginning of the field.
--- - `"end"`: Cursor is at the end of the field.
--- - `"delimiter"`: Cursor is at the delimiter after the field.
--- - `"inside"`: Cursor is inside the field.
---@alias CsvView.CursorAnchor "start" | "end" | "delimiter" | "inside"

---Get cursor information for the current position in the buffer.
---It checks whether the current line is a comment or a valid CSV row,
---and returns cursor information including CSV row/column and an "anchor" state.
---@param bufnr? integer Optional buffer number. Defaults to the current buffer if not provided.
---@return CsvView.Cursor cursor Cursor information
function M.get_cursor(bufnr)
  bufnr = M.resolve_bufnr(bufnr)

  -- Get the corresponding view for this buffer
  local view = require("csvview.view").get(bufnr)
  if not view then
    error("CsvView is not enabled for this buffer.")
  end

  -- Find the window in which this buffer is displayed
  local winid = M.buf_get_win(bufnr)
  if not winid then
    error("Could not find window for buffer " .. bufnr)
  end

  -- Get the (line, column) position of the cursor in the window
  local lnum, col_byte = unpack(vim.api.nvim_win_get_cursor(winid))
  local logical_row_number = view.metrics:get_logical_row_idx(lnum)
  local row = view.metrics:row({ lnum = lnum })
  if not row or not logical_row_number then
    error("Cursor is out of bounds.")
  end

  -- If this line is marked as a comment, return a CommentCursor
  if row.type == "comment" then
    return { kind = "comment", pos = { logical_row_number } }
  end

  -- Empty line
  if row:field_count() == 0 then
    return { kind = "empty_line", pos = { logical_row_number } }
  end

  local col_idx, range = view.metrics:get_logical_field_by_offet(lnum, col_byte)
  local lines = vim.api.nvim_buf_get_text(
    bufnr,
    range.start_row - 1, -- Convert to 0-based index
    range.start_col,
    range.end_row - 1, -- Convert to 0-based index
    range.end_col,
    {}
  )
  local text = table.concat(lines, "\n") -- Join lines if multiline

  -- Determine the anchor state of the cursor within this field
  ---@type CsvView.CursorAnchor
  local anchor
  if lnum == range.end_row and col_byte >= range.end_col then
    anchor = "delimiter"
  elseif lnum == range.start_row and col_byte == range.start_col then
    anchor = "start"
  elseif lnum == range.end_row then
    local last_line = lines[#lines]
    local offset_in_field = lnum == range.start_row and col_byte - range.start_col or col_byte
    -- Use `vim.fn.charidx()` to handle multibyte safety in indexing.
    local charlen = vim.fn.charidx(last_line, #last_line)
    local charidx = vim.fn.charidx(last_line, offset_in_field)
    anchor = charidx == charlen - 1 and "end" or "inside"
  else
    anchor = "inside"
  end

  return { --- @type CsvView.Cursor
    kind = "field",
    pos = { logical_row_number, col_idx },
    anchor = anchor,
    text = text,
  }
end

--- Resolve bufnr
---@param bufnr integer| nil
---@return integer
function M.resolve_bufnr(bufnr)
  if not bufnr or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  else
    return bufnr
  end
end

--- Get buffer attached window in tabpage
---@param tabpage integer
---@param bufnr integer
---@return integer[]
function M.buf_tabpage_win_find(tabpage, bufnr)
  return vim.tbl_filter(
    --- @param winid integer
    --- @return boolean
    function(winid)
      return vim.api.nvim_win_get_buf(winid) == bufnr
    end,
    vim.api.nvim_tabpage_list_wins(tabpage)
  )
end

--- Get buffer attached window
---@param bufnr integer
---@return integer?
function M.buf_get_win(bufnr)
  -- Prefer current window
  local current_win = vim.api.nvim_get_current_win()
  local current_buf = vim.api.nvim_win_get_buf(current_win)
  if current_buf == bufnr then
    return current_win
  end

  -- Find window
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == bufnr then
      return winid
    end
  end
  return nil
end

--- Watch buffer-update events
---@param bufnr integer
---@param callbacks vim.api.keyset.buf_attach
---@return fun() detach_bufevent
function M.buf_attach(bufnr, callbacks)
  local detached = false
  local function wrap_buf_attach_handler(cb)
    if not cb then
      return nil
    end

    return function(...)
      if detached then
        return true -- detach
      end

      return cb(...)
    end
  end

  local function attach_events()
    vim.api.nvim_buf_attach(bufnr, false, {
      on_lines = wrap_buf_attach_handler(callbacks.on_lines),
      on_bytes = wrap_buf_attach_handler(callbacks.on_bytes),
      on_changedtick = wrap_buf_attach_handler(callbacks.on_changedtick),
      on_reload = wrap_buf_attach_handler(callbacks.on_reload),
      on_detach = wrap_buf_attach_handler(callbacks.on_detach),
      preview = true, -- for inccommand
    })
  end

  -- Attach to buffer
  attach_events()

  -- Re-register events on `:e`
  local buf_event_auid = vim.api.nvim_create_autocmd({ "BufReadPost" }, {
    callback = function()
      attach_events()
      if callbacks.on_reload then
        callbacks.on_reload("reload", bufnr)
      end
    end,
    buffer = bufnr,
  })

  -- detach
  return function()
    if detached then
      return
    end

    vim.api.nvim_del_autocmd(buf_event_auid)
    detached = true
  end
end

--- @class CsvView.Error
--- @field err string error message
--- @field stacktrace? string error stacktrace
--- @field [string] any additional context data

--- Wrap error with stacktrace for `xpcall`
---@param err string|CsvView.Error|nil
---@return CsvView.Error
function M.wrap_stacktrace(err)
  if type(err) == "table" then
    return vim.tbl_deep_extend("keep", err, { stacktrace = debug.traceback("", 2) })
  else
    return { err = err, stacktrace = debug.traceback("", 2) }
  end
end

--- Propagate error with context
---@param err string|CsvView.Error|nil
---@param context table<string,any>| nil
function M.error_with_context(err, context)
  if type(err) == "string" then
    err = vim.tbl_deep_extend("keep", { err = err }, context or {})
  elseif type(err) == "table" then
    err = vim.tbl_deep_extend("keep", err, context or {})
  end
  error(err, 0)
end

--- Remove key from table
---@param tbl table
---@param key string
---@return any
local function tbl_remove_key(tbl, key)
  local value = tbl[key] ---@type any
  tbl[key] = nil ---@type any
  return value
end

--- Format error message
---@param err string|CsvView.Error|nil
---@return string
function M.format_error(err)
  if type(err) == "table" then
    local stacktrace = tbl_remove_key(err, "stacktrace") or "No stacktrace available"
    local err_msg = tbl_remove_key(err, "err") or "An unspecified error occurred"
    return string.format("Error: %s\nDetails: %s\n%s", err_msg, vim.inspect(err), stacktrace)
  elseif type(err) == "string" then
    return err
  else
    return "An unknown error occurred."
  end
end

--- Print error message
--- @type fun(header: string, err: string|CsvView.Error|nil)
M.print_structured_error = vim.schedule_wrap(function(header, err)
  local msg = M.format_error(err)
  vim.notify(string.format("%s\n\n%s", header, msg), vim.log.levels.ERROR, {
    title = "csvview.nvim",
  })
end)

--- Create a comment detection function based on parser options.
---
--- The returned function checks if a line is a comment by:
--- 1. Line number check: If `opts.parser.comment_lines` is set, any line with
---    lnum <= comment_lines is considered a comment (useful for header rows).
--- 2. Prefix check: If the line starts with any prefix in `opts.parser.comments`,
---    it is considered a comment (e.g., "#", "//").
---
---@param opts CsvView.InternalOptions
---@return fun(lnum: integer, line: string): boolean
function M.create_is_comment(opts)
  local comment_lines = opts.parser.comment_lines
  local comments = opts.parser.comments

  return function(lnum, line)
    -- check comment section
    if comment_lines and lnum <= comment_lines then
      return true
    end

    for _, comment in ipairs(comments) do
      if vim.startswith(line, comment) then
        return true
      end
    end
    return false
  end
end

--- Resolve delimiter character
---@param bufnr integer
---@param opts CsvView.InternalOptions
---@param quote_char string
---@return string
function M.resolve_delimiter(bufnr, opts, quote_char)
  local delim = opts.parser.delimiter
  ---@diagnostic disable-next-line: no-unknown
  local char
  if type(delim) == "function" then
    char = delim(bufnr)
  elseif type(delim) == "string" then
    char = delim
  elseif type(delim) == "table" then
    if type(delim.default) == "string" then ---@diagnostic disable-line: undefined-field
      -- Backwards compatibility for opts.parser.delimiter.default
      vim.deprecate("opts.parser.delimiter.default", "opts.parser.delimiter.fallbacks", "2.0.0", "csvview.nvim")
      delim.ft["csv"] = delim.default ---@diagnostic disable-line: undefined-field
    end
    -- If the delimiter is a table, it should contain a mapping of filetypes to delimiters.
    -- If the filetype is not found, it will try to detect the delimiter using the sniffer.
    char = delim.ft[vim.bo.filetype]
    if not char then
      char = require("csvview.sniffer").buf_detect_delimiter(
        bufnr,
        quote_char,
        M.create_is_comment(opts),
        opts.parser.max_lookahead,
        delim.fallbacks
      )
    end
  end

  assert(type(char) == "string", string.format("unknown delimiter type: %s", type(char)))
  return char
end

--- Get quote char character
---@param bufnr integer
---@param opts CsvView.InternalOptions
---@return string
function M.resolve_quote_char(bufnr, opts)
  local delim = opts.parser.quote_char
  ---@diagnostic disable-next-line: no-unknown
  local char
  if type(delim) == "string" then
    char = delim
  end

  assert(type(char) == "string", string.format("quote char must be a string, got %s", type(char)))
  assert(#char == 1, string.format("quote char must be a single character, got %s", char))
  return char
end

--- Get the line number of the header in the buffer
---@param bufnr integer
---@param opts CsvView.InternalOptions
---@param delimiter string
---@param quote_char string
---@return integer|nil
function M.resolve_header_lnum(bufnr, opts, delimiter, quote_char)
  local opts_header_lnum = opts.view.header_lnum

  local header_lnum ---@type integer|nil
  if type(opts_header_lnum) == "number" then
    -- If header_lnum is a number, use it as the header line number
    header_lnum = opts_header_lnum
  elseif opts_header_lnum == true then
    -- If header_lnum is true, auto detect the header line
    header_lnum = require("csvview.sniffer").buf_detect_header(
      bufnr,
      delimiter,
      quote_char,
      M.create_is_comment(opts),
      opts.parser.max_lookahead
    )
  else
    -- If header_lnum is false or nil, do not use a header line
    header_lnum = nil
  end

  return header_lnum
end

return M
