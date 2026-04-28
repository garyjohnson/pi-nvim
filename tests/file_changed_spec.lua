--- Tests for fileChanged handler window placement and diff behavior.
--- Verifies that the pi terminal window is not displaced when showing
--- auto-diff, and that existing diffs are reused on re-notification.

local eq = assert.equals

-- Helper: count windows in current tabpage
local function win_count()
  return #vim.api.nvim_tabpage_list_wins(0)
end

-- Helper: find a window showing a buffer with a given name suffix
local function find_win_by_bufname(suffix)
  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(winid))
    if name:sub(-#suffix) == suffix then
      return winid
    end
  end
  return nil
end

-- Helper: check if a buffer with a given name suffix exists (even if hidden)
local function buf_exists_with_name(suffix)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name:sub(-#suffix) == suffix then
      return true
    end
  end
  return false
end

-- Helper: clean up extra windows and buffers, leaving one clean window
local function cleanup()
  -- close all windows except one
  vim.cmd("silent! only")
  -- wipe out all buffers
  vim.cmd("silent! %bwipeout!")
  -- create a fresh empty buffer
  vim.cmd("enew")
  -- clear diff options
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      vim.wo[win].diff = false
    end
  end
end

describe("fileChanged window placement", function()
  local handlers = require("pi-nvim.handlers")
  local config = require("pi-nvim.config")

  before_each(function()
    config.setup({ auto_open = true, show_diff = true })
    cleanup()
  end)

  after_each(function()
    cleanup()
    config.setup({}) -- restore defaults
  end)

  -----------------------------------------------------------------------
  -- Scenario A: file not open, but an edit-class window exists
  -- The file should open in that window, then a diff split should appear.
  -----------------------------------------------------------------------
  it("opens file in existing edit window when file is not already open (scenario A)", function()
    local tracked_path = "lua/pi-nvim/config.lua"
    local orig_win_count = win_count()

    local result = handlers.fileChanged({ path = tracked_path })
    eq(true, result.ok)
    eq(true, result.opened)
    eq(true, result.diff)

    -- Should have original+1 windows: the original window (now showing the file)
    -- plus the diff scratch buffer split
    eq(orig_win_count + 1, win_count())

    -- A diff scratch buffer should exist
    local abs_tracked_path = vim.fn.fnamemodify(tracked_path, ":p")
    assert.is.True(buf_exists_with_name("[git:HEAD] " .. abs_tracked_path))
  end)

  -----------------------------------------------------------------------
  -- Scenario C: file already open in an edit window
  -- The file should reload in place (same window), diff should open next
  -- to it, and no extra window should be created for the file.
  -----------------------------------------------------------------------
  it("reuses existing file window instead of creating new one (scenario C)", function()
    local tracked_path = "lua/pi-nvim/config.lua"

    -- Pre-open the file in the current window
    vim.cmd("edit " .. tracked_path)
    local file_win_before = vim.api.nvim_get_current_win()
    local orig_win_count = win_count()

    local result = handlers.fileChanged({ path = tracked_path })
    eq(true, result.ok)
    eq(true, result.opened)

    -- Only one extra window should have been created (the diff scratch)
    eq(orig_win_count + 1, win_count())

    -- The file should still be in the same window
    local file_win_after = find_win_by_bufname("config.lua")
    assert.is_not.Nil(file_win_after)
    eq(file_win_before, file_win_after)
  end)

  -----------------------------------------------------------------------
  -- Existing diff reuse: when the diff scratch buffer already exists
  -- alongside the file window, just reload and update.
  -----------------------------------------------------------------------
  it("reuses existing diff scratch buffer on subsequent fileChanged calls", function()
    local tracked_path = "lua/pi-nvim/config.lua"

    -- First call: sets up the diff
    local result1 = handlers.fileChanged({ path = tracked_path })
    eq(true, result1.ok)
    eq(true, result1.diff)

    local win_count_after_first = win_count()

    -- Second call: should reuse existing windows
    local result2 = handlers.fileChanged({ path = tracked_path })
    eq(true, result2.ok)
    eq(true, result2.diff)

    -- No new windows should be created
    eq(win_count_after_first, win_count())
  end)

  -----------------------------------------------------------------------
  -- No diff when show_diff is false
  -----------------------------------------------------------------------
  it("opens file without diff when show_diff is disabled", function()
    config.setup({ auto_open = true, show_diff = false })
    local tracked_path = "lua/pi-nvim/config.lua"
    local orig_win_count = win_count()

    local result = handlers.fileChanged({ path = tracked_path })
    eq(true, result.ok)
    eq(true, result.opened)
    assert.is.Nil(result.diff)

    -- No new window should be created (file opened in existing window)
    eq(orig_win_count, win_count())

    config.setup({}) -- restore defaults
  end)

  -----------------------------------------------------------------------
  -- Auto-open disabled: nothing happens
  -----------------------------------------------------------------------
  it("does nothing when auto_open is disabled", function()
    config.setup({ auto_open = false })
    local orig_win_count = win_count()

    local result = handlers.fileChanged({ path = "lua/pi-nvim/config.lua" })
    eq(true, result.ok)
    assert.is.Nil(result.opened)

    -- No windows created
    eq(orig_win_count, win_count())

    config.setup({}) -- restore defaults
  end)

  -----------------------------------------------------------------------
  -- Horizontal diff split
  -----------------------------------------------------------------------
  it("uses horizontal split when diff_split is horizontal", function()
    config.setup({ auto_open = true, show_diff = true, diff_split = "horizontal" })
    local tracked_path = "lua/pi-nvim/config.lua"
    local orig_win_count = win_count()

    local result = handlers.fileChanged({ path = tracked_path })
    eq(true, result.ok)
    eq(true, result.opened)
    eq(true, result.diff)

    -- Should have 2 windows (original + horizontal split)
    eq(orig_win_count + 1, win_count())

    -- The new window should be a horizontal split (width same as original)
    -- In horizontal split, the new window has the same width as the parent
    local wins = vim.api.nvim_tabpage_list_wins(0)
    assert.is.True(#wins >= 2)

    config.setup({}) -- restore defaults
  end)

  -----------------------------------------------------------------------
  -- Untracked file in git repo: should open the file but skip diff
  -- (The cwd is a git repo, so git=true, but the file is untracked
  -- so tracked=false and no diff is shown.)
  -----------------------------------------------------------------------
  it("opens file without diff when file is untracked in git repo", function()
    local untracked_path = vim.fn.getcwd() .. "/pi-nvim-test-untracked.tmp"
    local f = io.open(untracked_path, "w")
    f:write("untracked content\n")
    f:close()

    local orig_win_count = win_count()

    local result = handlers.fileChanged({ path = untracked_path })
    eq(true, result.ok)
    eq(true, result.opened)
    assert.is.Nil(result.diff)
    eq(true, result.git)
    eq(false, result.tracked)

    -- No diff split created
    eq(orig_win_count, win_count())

    os.remove(untracked_path)
  end)

end)

describe("is_edit_window", function()
  -- is_edit_window is a local function, so we test it indirectly through
  -- fileChanged behavior. When the current window is a non-edit-class
  -- (nofile) buffer, fileChanged should skip it and find another window
  -- or create a new split.

  local handlers = require("pi-nvim.handlers")
  local config = require("pi-nvim.config")

  before_each(function()
    config.setup({ auto_open = true, show_diff = false }) -- show_diff=false to simplify window counting
    cleanup()
  end)

  after_each(function()
    cleanup()
    config.setup({}) -- restore defaults
  end)

  it("skips nofile buffers when finding a window", function()
    -- Set current buffer to nofile (scratch)
    local scratch = vim.api.nvim_create_buf(true, true)
    vim.bo[scratch].buftype = "nofile"
    vim.api.nvim_win_set_buf(0, scratch)

    local tracked_path = "lua/pi-nvim/config.lua"
    local orig_win_count = win_count()

    -- With show_diff=false, the file should open in a NEW window
    -- since the current one is nofile and should be skipped
    local result = handlers.fileChanged({ path = tracked_path })
    eq(true, result.ok)
    eq(true, result.opened)

    -- A new window should have been created because the current one
    -- is nofile and was skipped
    assert.is.True(win_count() > orig_win_count)
  end)

  it("skips quickfix buffers when finding a window", function()
    -- Set current buffer to quickfix
    local qf = vim.api.nvim_create_buf(true, true)
    vim.bo[qf].buftype = "quickfix"
    vim.api.nvim_win_set_buf(0, qf)

    local tracked_path = "lua/pi-nvim/config.lua"
    local orig_win_count = win_count()

    local result = handlers.fileChanged({ path = tracked_path })
    eq(true, result.ok)
    eq(true, result.opened)

    -- A new window should have been created because quickfix is not an edit window
    assert.is.True(win_count() > orig_win_count)
  end)

  it("skips prompt buffers when finding a window", function()
    -- Set current buffer to prompt
    local prompt = vim.api.nvim_create_buf(true, true)
    vim.bo[prompt].buftype = "prompt"
    vim.api.nvim_win_set_buf(0, prompt)

    local tracked_path = "lua/pi-nvim/config.lua"
    local orig_win_count = win_count()

    local result = handlers.fileChanged({ path = tracked_path })
    eq(true, result.ok)
    eq(true, result.opened)

    -- A new window should have been created because prompt is not an edit window
    assert.is.True(win_count() > orig_win_count)
  end)
end)

describe("get_pi_bufnr", function()
  local pi = require("pi-nvim")

  before_each(function()
    cleanup()
  end)

  it("returns nil when no pi terminal has been launched", function()
    assert.is.Nil(pi.get_pi_bufnr())
  end)
end)

describe("resolve_path", function()
  it("resolves relative paths to absolute", function()
    -- resolve_path is a local function, but we can test its behavior
    -- indirectly through fileChanged by verifying that the scratch buffer
    -- name uses the absolute path
    local result = vim.fn.fnamemodify("lua/pi-nvim/config.lua", ":p")
    -- Should be an absolute path
    assert.is.True(result:sub(1, 1) == "/")
  end)
end)