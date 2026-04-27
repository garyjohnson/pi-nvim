--- JSON-RPC method handlers for pi-nvim.
--- Each handler receives a params table and returns a result table.
--- For errors, return server.error_result(code, message).
local M = {}

local server = require("pi-nvim.server")
local config = require("pi-nvim.config")

---------------------------------------------------------------------------
-- Git helpers
---------------------------------------------------------------------------

--- Check if a path is inside a git repository.
---@param path string File path to check
---@return boolean True if path is inside a git repo
local function is_git_repo(path)
  local dir = vim.fn.fnamemodify(path, ":p:h")
  while dir ~= "" and dir ~= "/" do
    if vim.fn.isdirectory(dir .. "/.git") == 1 then
      return true
    end
    dir = vim.fn.fnamemodify(dir, ":h")
  end
  return false
end

--- Get the git version of a file.
---@param path string File path
---@return string|nil content The file content at HEAD, or nil on failure
local function get_git_version(path)
  local cmd = string.format("git show HEAD:%s 2>/dev/null", vim.fn.shellescape(path))
  local output = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return output
end

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

  -- Validate types for optional numeric params
  if start_line ~= nil and type(start_line) ~= "number" then
    return server.error_result(-32602, string.format("Invalid params: start must be a number, got %s", type(start_line)))
  end
  if end_line ~= nil and type(end_line) ~= "number" then
    return server.error_result(-32602, string.format("Invalid params: end must be a number, got %s", type(end_line)))
  end

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

  -- Sanitize path: reject paths containing pipe, newline, or carriage
  -- return characters that could be used for VimScript command injection.
  -- The pipe character | chains ex commands; newlines terminate them.
  if path:find('|') or path:find('\n') or path:find('\r') then
    return server.error_result(-32602, "Invalid path: contains disallowed characters")
  end

  local line = params.line
  local col = params.col

  -- Validate types for optional numeric params
  if line ~= nil and type(line) ~= "number" then
    return server.error_result(-32602, string.format("Invalid params: line must be a number, got %s", type(line)))
  end
  if col ~= nil and type(col) ~= "number" then
    return server.error_result(-32602, string.format("Invalid params: col must be a number, got %s", type(col)))
  end

  -- Get configuration options
  local cfg = config.get()
  local use_split = cfg.open_in_split
  local split_dir = cfg.split_direction or "vertical"
  local show_diff = cfg.show_git_diff

  if use_split or show_diff then
    -- Check if we can show git diff
    local can_show_diff = show_diff and is_git_repo(path)
    local diff_output = nil

    if can_show_diff then
      -- Get inline git diff output
      local cmd = string.format("cd %s && git diff --no-color 2>/dev/null", vim.fn.shellescape(vim.fn.fnamemodify(path, ":p:h")))
      diff_output = vim.fn.system(cmd)
      if vim.v.shell_error ~= 0 or diff_output == "" then
        diff_output = nil
        can_show_diff = false
      end
    end

    -- Open the file first (optionally in a split)
    if use_split then
      if split_dir == "horizontal" then
        vim.cmd("split")
      else
        vim.cmd("vsplit")
      end
    end

    pcall(vim.cmd.edit, path)

    if line then
      local target_col = col or 1
      pcall(vim.api.nvim_win_set_cursor, 0, { line, target_col - 1 })
    end

    -- If we have diff output, create a new buffer with inline diff
    if can_show_diff and diff_output then
      -- Split off a new window for the diff
      vim.cmd("split")

      -- Set the diff content in the new buffer
      local diff_lines = vim.fn.split(diff_output, '\n', { trimempty = true })
      vim.api.nvim_buf_set_lines(0, 0, -1, false, diff_lines)

      -- Set filetype to diff
      vim.bo[0].filetype = "diff"

      -- Make it read-only
      vim.bo[0].modifiable = false

      -- Position at the first hunk
      vim.cmd("normal! gg")
    end
  else
    -- Original behavior: edit in current window
    pcall(vim.cmd.edit, path)

    if line then
      local target_col = col or 1
      pcall(vim.api.nvim_win_set_cursor, 0, { line, target_col - 1 })
    end
  end

  -- Find the buffer by name
  local bufnr = vim.fn.bufnr(path)
  if bufnr == -1 then
    bufnr = vim.json.null
  end

  return {
    bufnr = bufnr,
    name = path,
    useSplit = use_split,
    showDiff = show_diff and is_git_repo(path),
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