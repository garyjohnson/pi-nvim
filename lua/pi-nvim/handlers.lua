--- JSON-RPC method handlers for pi-nvim.
--- Each handler receives a params table and returns a result table.
--- For errors, return server.error_result(code, message).
local M = {}

local server = require("pi-nvim.server")

---------------------------------------------------------------------------
-- initialize
---------------------------------------------------------------------------

function M.initialize(_params)
  return {
    protocolVersion = 1,
    pid = vim.fn.getpid(),
  }
end

---------------------------------------------------------------------------
-- state
---------------------------------------------------------------------------

function M.state(_params)
  local buffers = {}
  local buf_list = vim.api.nvim_list_bufs()

  for _, bufnr in ipairs(buf_list) do
    -- Only list loaded/listed buffers
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].buflisted then
      local name = vim.api.nvim_buf_get_name(bufnr)
      local windows = {}
      for _, winid in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(winid) == bufnr then
          table.insert(windows, winid)
        end
      end

      table.insert(buffers, {
        bufnr = bufnr,
        name = name,
        listed = true,
        modified = vim.bo[bufnr].modified,
        lineCount = vim.api.nvim_buf_line_count(bufnr),
        filetype = vim.bo[bufnr].filetype,
        windows = windows,
      })
    end
  end

  -- Windows with cursor positions and viewport info
  local windows = {}
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    local bufnr = vim.api.nvim_win_get_buf(winid)
    local cursor = vim.api.nvim_win_get_cursor(winid)
    -- topline/botline: use Vim's internal scroll info
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    local topline = vim.fn.line("w0", winid)
    local botline = vim.fn.line("w$", winid)

    table.insert(windows, {
      winid = winid,
      bufnr = bufnr,
      cursor = { cursor[1], cursor[2] }, -- 1-indexed row, 0-indexed col
      topline = topline,
      botline = botline,
    })
  end

  -- Current mode
  local mode_info = vim.api.nvim_get_mode()
  local mode = mode_info.mode

  -- Current window
  local current_win = vim.api.nvim_get_current_win()

  -- Last focused buffer (buffer in current window)
  local last_buffer = vim.api.nvim_get_current_buf()

  -- Selection info (position only, no text)
  local selection = nil
  if mode == "v" or mode == "V" or mode == "\22" then -- \22 is ctrl-v (visual block)
    local bufnr = vim.api.nvim_get_current_buf()
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")

    selection = {
      mode = mode,
      bufnr = bufnr,
      name = vim.api.nvim_buf_get_name(bufnr),
      start = { start_pos[2], start_pos[3] }, -- 1-indexed line, col
      ["end"] = { end_pos[2], end_pos[3] },    -- 1-indexed line, col
    }
  end

  return {
    mode = mode,
    currentWin = current_win,
    lastBuffer = last_buffer,
    buffers = buffers,
    windows = windows,
    selection = selection,
  }
end

---------------------------------------------------------------------------
-- bufContent
---------------------------------------------------------------------------

function M.bufContent(params)
  local bufnr = params.bufnr

  if type(bufnr) ~= "number" then
    return server.error_result(-32602, string.format("Invalid params: bufnr must be a number, got %s", type(bufnr)))
  end

  if not vim.api.nvim_buf_is_valid(bufnr) then
    return server.error_result(-32001, string.format("Buffer not valid: %d", bufnr))
  end

  local start_line = params.start
  local end_line = params["end"] -- "end" is reserved in Lua

  local total_lines = vim.api.nvim_buf_line_count(bufnr)

  -- Default to full buffer
  start_line = start_line or 1
  end_line = end_line or total_lines

  -- Clamp to valid range
  start_line = math.max(1, start_line)
  end_line = math.min(total_lines, end_line)

  if start_line > end_line then
    return server.error_result(-32602, string.format("Invalid range: start=%d, end=%d", start_line, end_line))
  end

  -- nvim_buf_get_lines is 0-indexed, end-exclusive
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)

  return {
    bufnr = bufnr,
    name = vim.api.nvim_buf_get_name(bufnr),
    start = start_line,
    ["end"] = end_line,
    lines = lines,
    totalLines = total_lines,
  }
end

---------------------------------------------------------------------------
-- selection
---------------------------------------------------------------------------

function M.selection(_params)
  local mode_info = vim.api.nvim_get_mode()
  local mode = mode_info.mode

  if mode ~= "v" and mode ~= "V" and mode ~= "\22" then
    -- No visual selection active
    return {
      mode = mode,
      bufnr = vim.json.null,
      name = vim.json.null,
      start = vim.json.null,
      ["end"] = vim.json.null,
      text = vim.json.null,
    }
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local start_line = start_pos[2]
  local start_col = start_pos[3]
  local end_line = end_pos[2]
  local end_col = end_pos[3]

  -- Get the selected text
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  local text
  if #lines == 0 then
    text = ""
  elseif #lines == 1 then
    -- Single line: substring
    text = string.sub(lines[1], start_col, end_col)
  else
    -- Multi-line: first line from start_col, middle lines full, last line to end_col
    lines[1] = string.sub(lines[1], start_col)
    lines[#lines] = string.sub(lines[#lines], 1, end_col)
    text = table.concat(lines, "\n")
  end

  return {
    mode = mode,
    bufnr = bufnr,
    name = vim.api.nvim_buf_get_name(bufnr),
    start = { start_line, start_col },
    ["end"] = { end_line, end_col },
    text = text,
  }
end

---------------------------------------------------------------------------
-- openFile
---------------------------------------------------------------------------

function M.openFile(params)
  local path = params.path
  if not path or path == "" then
    return server.error_result(-32602, "Missing required param: path")
  end

  local line = params.line
  local col = params.col

  -- Use schedule to ensure we're on the main thread
  -- (handlers may be called from libuv callbacks)
  local ok, err = pcall(function()
    vim.schedule(function()
      vim.cmd(string.format("edit %s", vim.fn.fnameescape(path)))
      if line then
        local target_col = col or 1
        vim.api.nvim_win_set_cursor(0, { line, target_col - 1 }) -- col is 0-indexed for API
      end
    end)
  end)

  if not ok then
    return server.error_result(-32603, string.format("Failed to open file: %s", err))
  end

  -- Find the buffer (may not exist yet if vim.schedule hasn't run)
  -- Try to find by name
  local bufnr = vim.fn.bufnr(path)
  if bufnr == -1 then
    -- Buffer doesn't exist yet, will be created by edit command
    bufnr = vim.json.null
  end

  return {
    bufnr = bufnr,
    name = path,
  }
end

---------------------------------------------------------------------------
-- Register all handlers with the server
---------------------------------------------------------------------------

function M.register_all()
  server.register_method("initialize", M.initialize)
  server.register_method("state", M.state)
  server.register_method("bufContent", M.bufContent)
  server.register_method("selection", M.selection)
  server.register_method("openFile", M.openFile)
end

return M