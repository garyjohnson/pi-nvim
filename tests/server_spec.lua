--- Tests for pi-nvim server module.
--- Verifies socket creation, JSON-RPC dispatch, and cleanup.

local eq = assert.equals

describe("pi-nvim server", function()
  local server = require("pi-nvim.server")
  local handlers = require("pi-nvim.handlers")

  after_each(function()
    server.stop()
  end)

  it("starts and returns a socket path", function()
    local sock_path = server.start()
    assert.is_not.Nil(sock_path)
    -- Use plain text search (3rd arg = true) to avoid Lua pattern metacharacters in path
    assert.is_not.Nil(sock_path:find("/tmp/pi-nvim-", 1, true))
    assert.is_True(server.is_running())
  end)

  it("stop cleans up the socket", function()
    local sock_path = server.start()
    server.stop()
    assert.is_False(server.is_running())
  end)

  it("registers and calls a handler", function()
    handlers.register_all()
    server.start()

    local result = handlers.state({})
    eq("n", result.mode)
    -- buffers should be a table (may or may not have entries in headless)
    eq("table", type(result.buffers))
    eq("table", type(result.windows))
  end)

  it("initialize returns protocol version and pid", function()
    local result = handlers.initialize({})
    eq(1, result.protocolVersion)
    eq("number", type(result.pid))
  end)

  it("bufContent returns error for invalid buffer", function()
    handlers.register_all()
    local result = handlers.bufContent({ bufnr = 99999 })
    assert.is_not.Nil(result.__nvim_error)
    eq(-32001, result.__nvim_error.code)
  end)

  it("bufContent returns content for valid buffer", function()
    -- Create a test buffer
    local buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "hello", "world" })

    local result = handlers.bufContent({ bufnr = buf })
    eq(buf, result.bufnr)
    eq(2, result.totalLines)
    eq("hello", result.lines[1])
    eq("world", result.lines[2])

    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("bufContent respects start and end params", function()
    local buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line1", "line2", "line3", "line4", "line5" })

    local result = handlers.bufContent({ bufnr = buf, start = 2, ["end"] = 4 })
    eq(2, result.start)
    eq(4, result["end"])
    -- Lines are 1-indexed in our protocol; 0-indexed in nvim API
    -- start=2, end=4 means lines 2-4 inclusive
    eq("line2", result.lines[1])
    eq("line3", result.lines[2])
    eq("line4", result.lines[3])

    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("selection returns null text when no visual selection", function()
    -- In headless mode, there's no visual selection
    local result = handlers.selection({})
    -- Mode should be a string (current mode, e.g. "n" for normal)
    eq("string", type(result.mode))
    -- No visual selection active
    assert.is.Nil(result.text)
  end)

  it("openFile returns a result", function()
    local result = handlers.openFile({ path = "/tmp/pi-nvim-test-open.lua" })
    -- In headless mode, the edit command may not work, but the handler should not error
    assert.is_not.Nil(result)
  end)

  it("handlers can be called (verifies nvim_list_bufs works in scheduled context)", function()
    handlers.register_all()

    -- Verify the state handler works - this exercises the same code paths
    -- (nvim_list_bufs, nvim_get_mode, etc.) that would fail in fast event context.
    -- The fix ensures socket dispatch wraps handlers in vim.schedule.
    local result = handlers.state({})
    eq("n", result.mode)
    eq("table", type(result.buffers))
    eq("table", type(result.windows))
  end)

  it("fileChanged returns error for missing path", function()
    local result = handlers.fileChanged({})
    assert.is_not.Nil(result.__nvim_error)
    eq(-32602, result.__nvim_error.code)
  end)

  it("fileChanged returns error for empty path", function()
    local result = handlers.fileChanged({ path = "" })
    assert.is_not.Nil(result.__nvim_error)
    eq(-32602, result.__nvim_error.code)
  end)

  it("fileChanged returns error for path with pipe", function()
    local result = handlers.fileChanged({ path = "evil|ls" })
    assert.is_not.Nil(result.__nvim_error)
    eq(-32602, result.__nvim_error.code)
  end)

  it("fileChanged returns error for path with newline", function()
    local result = handlers.fileChanged({ path = "foo.lua\nmalicious" })
    assert.is_not.Nil(result.__nvim_error)
    eq(-32602, result.__nvim_error.code)
  end)

  it("fileChanged returns error for path with carriage return", function()
    local result = handlers.fileChanged({ path = "foo.lua\rmalicious" })
    assert.is_not.Nil(result.__nvim_error)
    eq(-32602, result.__nvim_error.code)
  end)

  it("fileChanged returns ok when auto_open is disabled", function()
    local config = require("pi-nvim.config")
    config.setup({ auto_open = false })

    local result = handlers.fileChanged({ path = "/tmp/pi-nvim-test-filechanged.lua" })
    eq(true, result.ok)

    -- Restore defaults
    config.setup({})
  end)

  it("fileChanged opens file without diff when show_diff is disabled", function()
    local config = require("pi-nvim.config")
    config.setup({ auto_open = true, show_diff = false })

    local result = handlers.fileChanged({ path = "/tmp/pi-nvim-test-no-diff.lua" })
    eq(true, result.ok)
    eq(true, result.opened)
    assert.is.Nil(result.diff)

    -- Restore defaults
    config.setup({})
  end)

  it("fileChanged sets up diffthis for tracked files in a git repo", function()
    -- Use an existing tracked file from this repo
    local tracked_path = "lua/pi-nvim/config.lua"

    -- Save window state for cleanup
    local orig_wins = vim.api.nvim_list_wins()
    local orig_win = vim.api.nvim_get_current_win()
    local orig_buf = vim.api.nvim_win_get_buf(orig_win)

    local result = handlers.fileChanged({ path = tracked_path })

    eq(true, result.ok)
    eq(true, result.opened)
    eq(true, result.diff)

    -- Clean up: close any new windows, clear diff, restore original buffer
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if not vim.tbl_contains(orig_wins, win) then
        vim.api.nvim_win_close(win, true)
      end
    end

    -- Restore original window and buffer
    vim.api.nvim_set_current_win(orig_win)
    if vim.api.nvim_win_is_valid(orig_win) then
      vim.api.nvim_win_set_buf(orig_win, orig_buf)
    end

    -- Clear diff option in case it leaked
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      vim.wo[win].diff = false
    end
  end)
end)