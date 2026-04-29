--- JSON-RPC method handlers for pi-nvim.
--- Each handler receives a params table and returns a result table.
--- For errors, return server.error_result(code, message).
local M = {}

local server = require("pi-nvim.server")
local config = require("pi-nvim.config")

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

--- Resolve a path to its absolute form for reliable comparisons.
local function resolve_path(path)
  return vim.fn.fnamemodify(path, ":p")
end

--- Close any diff scratch windows/buffers in the current tabpage that
--- don't belong to the given file.  If keep_for_path is nil, close all
--- scratch windows.  Also clears diff mode on paired file windows.
local function cleanup_diffs(keep_for_path)
  local keep_abs = keep_for_path and resolve_path(keep_for_path) or nil
  local keep_suffix = keep_abs and ("[git:HEAD] " .. keep_abs) or nil
  local closed_any = false

  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local bufnr = vim.api.nvim_win_get_buf(winid)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name:find("[git:HEAD]", 1, true) then
      local should_close = not keep_suffix or name:sub(-#keep_suffix) ~= keep_suffix
      if should_close then
        pcall(vim.api.nvim_win_close, winid, true)
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
        closed_any = true
      end
    end
  end

  -- Also delete hidden scratch buffers (not in any window).
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name:find("[git:HEAD]", 1, true) then
      local should_delete = not keep_suffix or name:sub(-#keep_suffix) ~= keep_suffix
      if should_delete then
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
        closed_any = true
      end
    end
  end

  if closed_any then
    -- Turn off diff mode in all windows that lost their scratch pair.
    -- We use :diffoff! because :diffoff only works in the current window
    -- and the current window may just have been closed.
    pcall(vim.cmd, "diffoff!")
  end
end

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

  -- Clean up any stale diff scratch windows for other files before
  -- opening, so we don't end up with mismatched diffs.
  cleanup_diffs(path)

  -- Use vim.cmd.edit (function form) to avoid string interpolation
  -- vulnerabilities. The function form takes a plain filename, not
  -- an ex command, so pipe characters and other ex metacharacters
  -- in the path cannot inject commands.
  local ok, _ = pcall(vim.cmd.edit, path)

  -- edit may fail for nonexistent files, but still opens a buffer.
  -- Only true errors (permission, etc.) propagate. pcall catches them.

  if line then
    local target_col = col or 1
    pcall(vim.api.nvim_win_set_cursor, 0, { line, target_col - 1 })
  end

  -- Find the buffer by name
  local bufnr = vim.fn.bufnr(path)
  if bufnr == -1 then
    bufnr = vim.json.null
  end

  return {
    bufnr = bufnr,
    name = path,
  }
end

---------------------------------------------------------------------------
-- fileChanged
---------------------------------------------------------------------------

--- Check if a window is suitable for placing a file or diff buffer.
--- Skips terminal buffers, nofile/scratch buffers, quickfix, and prompts.
local function is_edit_window(winid)
  local bufnr = vim.api.nvim_win_get_buf(winid)
  local bt = vim.bo[bufnr].buftype
  if bt == "terminal" then return false end
  if bt == "nofile" or bt == "quickfix" or bt == "prompt" then return false end
  return true
end

function M.fileChanged(params)
  local path = params.path
  if not path or path == "" then
    return server.error_result(-32602, "Missing required param: path")
  end

  -- Same sanitization as openFile
  if path:find('|') or path:find('\n') or path:find('\r') then
    return server.error_result(-32602, "Invalid path: contains disallowed characters")
  end

  local opts = config.get()

  -- Auto-open disabled: nothing to do
  if not opts.auto_open then
    return { ok = true }
  end

  local pi = require("pi-nvim")
  local pi_bufnr = pi.get_pi_bufnr()
  local abs_path = resolve_path(path)

  -- Clean up any stale diff scratch windows for other files so we
  -- don't end up with mismatched diffs in this tabpage.
  cleanup_diffs(path)

  local tabpage = vim.api.nvim_get_current_tabpage()
  local wins = vim.api.nvim_tabpage_list_wins(tabpage)

  ------------------------------------------------------------------------
  -- Try to find an existing diff scratch buffer for this file in the
  -- current tabpage.  If one exists, just reload the file buffer —
  -- the diff will update automatically.
  ------------------------------------------------------------------------
  -- nvim_buf_set_name resolves relative paths, so we always label
  -- scratch buffers with the absolute path.  Use suffix matching to
  -- find them regardless of how the name was stored.
  local scratch_suffix = "[git:HEAD] " .. abs_path
  local function is_scratch_buf(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    return name:sub(-#scratch_suffix) == scratch_suffix
  end

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if is_scratch_buf(bufnr) then
      local file_win, scratch_win
      for _, winid in ipairs(wins) do
        local wbuf = vim.api.nvim_win_get_buf(winid)
        if wbuf == bufnr then scratch_win = winid end
        if resolve_path(vim.api.nvim_buf_get_name(wbuf)) == abs_path then
          file_win = winid
        end
      end
      if file_win and scratch_win then
        -- Both windows exist — reload the file buffer and refresh diff
        vim.api.nvim_set_current_win(file_win)
        vim.cmd("checktime")
        vim.cmd("diffupdate")
        return { ok = true, opened = true, diff = true }
      end
      -- Scratch buffer exists but not visible in this tab — fall through
      -- to create a fresh diff setup below.
      break
    end
  end

  ------------------------------------------------------------------------
  -- Find or create a window for the file, without displacing the pi
  -- terminal.
  --
  -- Algorithm:
  --   1. Look for an edit-class window already showing the file.
  --   2. Look for any other edit-class window to open the file in.
  --   3. If only terminal windows exist, split off the pi window.
  ------------------------------------------------------------------------

  --- Find a window in the current tabpage showing the file, skipping
  --- terminal and scratch windows.
  local function find_file_window()
    for _, winid in ipairs(wins) do
      if is_edit_window(winid) then
        local bufnr = vim.api.nvim_win_get_buf(winid)
        if resolve_path(vim.api.nvim_buf_get_name(bufnr)) == abs_path then
          return winid
        end
      end
    end
    return nil
  end

  --- Find any edit-class window in the current tabpage (not showing the
  --- file, preferring the current window).
  local function find_available_window()
    -- Prefer the current window if it's suitable
    local cur = vim.api.nvim_get_current_win()
    if is_edit_window(cur) then return cur end
    -- Fall back to any edit-class window
    for _, winid in ipairs(wins) do
      if is_edit_window(winid) then return winid end
    end
    return nil
  end

  local file_win = find_file_window()

  if file_win then
    -- Scenario C: file already open — reload it from disk
    vim.api.nvim_set_current_win(file_win)
    vim.cmd("checktime")
  else
    local avail_win = find_available_window()
    if avail_win then
      -- Scenario A: reuse an available edit window
      vim.api.nvim_set_current_win(avail_win)
      pcall(vim.cmd.edit, path)
    else
      -- Scenario B: only terminal windows — split off pi
      local pi_win
      if pi_bufnr then
        for _, winid in ipairs(wins) do
          if vim.api.nvim_win_get_buf(winid) == pi_bufnr then
            pi_win = winid
            break
          end
        end
      end
      if pi_win then
        vim.api.nvim_set_current_win(pi_win)
      end
      vim.cmd("rightbelow vsplit")
      pcall(vim.cmd.edit, path)
    end
  end

  if not opts.show_diff then
    return { ok = true, opened = true }
  end

  local file_bufnr = vim.api.nvim_get_current_buf()

  -- Check if the file is in a git repo
  local git_root = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null")
  if vim.v.shell_error ~= 0 or git_root == "" then
    return { ok = true, opened = true, git = false }
  end

  git_root = git_root:gsub("\n$", "")

  -- Check if file is tracked by git
  local tracked = vim.fn.system("git ls-files --error-unmatch " .. vim.fn.shellescape(path) .. " 2>/dev/null")
  if vim.v.shell_error ~= 0 then
    return { ok = true, opened = true, git = true, tracked = false }
  end

  -- Get repo-relative path for git show
  local relpath = vim.fn.system("git ls-files --full-name " .. vim.fn.shellescape(path) .. " 2>/dev/null")
  relpath = relpath:gsub("\n$", "")

  -- Get HEAD version of the file
  local head_content = vim.fn.system(
    "git -C " .. vim.fn.shellescape(git_root) .. " show HEAD:" .. vim.fn.shellescape(relpath) .. " 2>/dev/null"
  )

  if vim.v.shell_error ~= 0 then
    return { ok = true, opened = true, git = true, tracked = true, head = false }
  end

  -- Check for an existing scratch buffer with this name (e.g. from a
  -- prior fileChanged call).  If one exists, delete it so we can create a
  -- fresh one — the content may have changed.
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if is_scratch_buf(bufnr) then
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      break
    end
  end

  -- Create scratch buffer with HEAD content
  local scratch_buf = vim.api.nvim_create_buf(false, true)
  local lines = vim.split(head_content, "\n", { plain = true })

  -- Remove trailing empty line (files end with newline)
  if #lines > 0 and lines[#lines] == "" then
    table.remove(lines)
  end

  vim.api.nvim_buf_set_lines(scratch_buf, 0, -1, false, lines)

  -- Buffer options
  vim.bo[scratch_buf].buftype = "nofile"
  vim.bo[scratch_buf].modifiable = false
  vim.bo[scratch_buf].buflisted = false
  vim.bo[scratch_buf].filetype = vim.bo[file_bufnr].filetype

  -- Label the scratch buffer (nvim_buf_set_name may resolve relative
  -- paths to absolute, so use the absolute form for consistency.)
  local scratch_name = "[git:HEAD] " .. abs_path
  vim.api.nvim_buf_set_name(scratch_buf, scratch_name)

  -- Open scratch in split relative to the file window (which is now current)
  if opts.diff_split == "vertical" then
    vim.cmd("rightbelow vsplit")
  else
    vim.cmd("rightbelow split")
  end

  local scratch_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(scratch_win, scratch_buf)

  -- Enable diff mode on both windows
  vim.cmd("diffthis")
  vim.cmd("wincmd p")
  local file_win = vim.api.nvim_get_current_win()
  vim.cmd("diffthis")
  vim.cmd("diffupdate")

  -- Align winbars: if the file window has a winbar set (e.g. by
  -- barbecue/navic), give the scratch window a matching winbar so
  -- the two diff halves don't become vertically misaligned.
  local file_winbar = vim.wo[file_win].winbar
  if file_winbar and file_winbar ~= "" then
    -- Use a label with the filename to provide context.
    -- Escape any % in the path (winbar uses statusline syntax).
    local label = " [git:HEAD] " .. vim.fn.fnamemodify(abs_path, ":t")
    vim.wo[scratch_win].winbar = label:gsub("%%", "%%%%")
  end

  return { ok = true, opened = true, diff = true }
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
  server.register_method("fileChanged", M.fileChanged)
end

return M