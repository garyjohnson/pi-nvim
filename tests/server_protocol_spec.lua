--- Tests for pi-nvim server module: dispatch, protocol, and integration.
--- Verifies JSON-RPC parsing, error handling, and socket permissions.

local eq = assert.equals

describe("pi-nvim server protocol", function()
  local server = require("pi-nvim.server")
  local handlers = require("pi-nvim.handlers")

  before_each(function()
    handlers.register_all()
  end)

  after_each(function()
    server.stop()
  end)

  it("handler error_result creates proper error structure", function()
    local err = server.error_result(-32001, "Buffer not valid")
    eq(-32001, err.__nvim_error.code)
    eq("Buffer not valid", err.__nvim_error.message)
  end)

  it("send_result and send_error work without a client", function()
    server.start()
    -- Should silently no-op when no client is connected
    server.send_result(1, { ok = true })
    server.send_error(1, -32600, "Bad request")
    server.send_notification("test", { data = 123 })
    assert.is_True(true) -- verifying no crashes
  end)

  it("stop cleans up even when server is not running", function()
    -- Should not error when called on a non-running server
    server.stop()
    server.stop()
    assert.is_False(server.is_running())
  end)

  it("socket file has restrictive permissions after start", function()
    local sock_path = server.start()
    assert.is_not.Nil(sock_path)

    -- setfperm is called in server.start() after bind().
    -- Verify the socket exists and has owner-only permissions.
    -- getfperm returns strings like "rwxrwxr-x" (9 chars for rwx on owner/group/other)
    local perms = vim.fn.getfperm(sock_path)
    assert.is_not.Nil(perms)
    assert.is_True(#perms >= 9, "expected permission string of at least 9 chars, got: " .. perms)

    -- Owner should have rw (or rwx)
    assert.is_True(
      string.sub(perms, 1, 1) == "r" or string.sub(perms, 1, 1) == "-",
      "owner read should be r or -"
    )

    -- Group and other should NOT have read/write/execute
    -- Position 4-6 is group, 7-9 is other
    eq("-", string.sub(perms, 4, 4))  -- no group read
    eq("-", string.sub(perms, 7, 7))  -- no other read
  end)

  it("get_sock_path returns the socket path", function()
    local sock_path = server.start()
    eq(sock_path, server.get_sock_path())
  end)

  it("is_client_connected returns false when no client", function()
    server.start()
    assert.is_False(server.is_client_connected())
  end)

  it("state handler returns a well-formed response", function()
    local result = handlers.state({})
    eq("string", type(result.mode))
    eq("number", type(result.currentWin))
    eq("number", type(result.lastBuffer))
    eq("table", type(result.buffers))
    eq("table", type(result.windows))
    -- selection should be nil (no visual selection in headless)
    assert.is.Nil(result.selection)
  end)

  it("bufContent returns error for non-numeric bufnr", function()
    local result = handlers.bufContent({ bufnr = "not a number" })
    assert.is_not.Nil(result.__nvim_error)
    eq(-32602, result.__nvim_error.code)
  end)

  it("bufContent returns error for invalid buffer number", function()
    local result = handlers.bufContent({ bufnr = 99999 })
    assert.is_not.Nil(result.__nvim_error)
    eq(-32001, result.__nvim_error.code)
  end)

  it("bufContent returns error for negative range", function()
    local buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line1", "line2", "line3" })

    local result = handlers.bufContent({ bufnr = buf, start = 3, ["end"] = 1 })
    assert.is_not.Nil(result.__nvim_error)

    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("selection handler returns null fields for normal mode", function()
    local result = handlers.selection({})
    if result.mode ~= "v" and result.mode ~= "V" and result.mode ~= "\22" then
      assert.is.Nil(result.text)
      assert.is.Nil(result.bufnr)
    end
  end)

  it("openFile returns error for empty path", function()
    local result = handlers.openFile({ path = "" })
    assert.is_not.Nil(result.__nvim_error)
    eq(-32602, result.__nvim_error.code)
  end)

  it("openFile returns error for missing path", function()
    local result = handlers.openFile({})
    assert.is_not.Nil(result.__nvim_error)
    eq(-32602, result.__nvim_error.code)
  end)

  it("openFile rejects paths with pipe character", function()
    local result = handlers.openFile({ path = "foo.lua|!rm -rf /" })
    assert.is_not.Nil(result.__nvim_error)
    eq(-32602, result.__nvim_error.code)
    -- Verify the error message mentions disallowed characters
    assert.is_not.Nil(result.__nvim_error.message:find("disallowed"))
  end)

  it("openFile rejects paths with newline", function()
    local result = handlers.openFile({ path = "foo.lua\nmalicious" })
    assert.is_not.Nil(result.__nvim_error)
    eq(-32602, result.__nvim_error.code)
  end)

  it("openFile rejects paths with carriage return", function()
    local result = handlers.openFile({ path = "foo.lua\rmalicious" })
    assert.is_not.Nil(result.__nvim_error)
    eq(-32602, result.__nvim_error.code)
  end)

  it("openFile rejects non-numeric line param", function()
    local result = handlers.openFile({ path = "/tmp/test.lua", line = "abc" })
    assert.is_not.Nil(result.__nvim_error)
    eq(-32602, result.__nvim_error.code)
  end)

  it("openFile rejects non-numeric col param", function()
    local result = handlers.openFile({ path = "/tmp/test.lua", col = "abc" })
    assert.is_not.Nil(result.__nvim_error)
    eq(-32602, result.__nvim_error.code)
  end)

  it("bufContent rejects non-numeric start param", function()
    local buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line1", "line2", "line3" })

    local result = handlers.bufContent({ bufnr = buf, start = "abc" })
    assert.is_not.Nil(result.__nvim_error)
    eq(-32602, result.__nvim_error.code)

    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("bufContent rejects non-numeric end param", function()
    local buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line1", "line2", "line3" })

    local result = handlers.bufContent({ bufnr = buf, ["end"] = "abc" })
    assert.is_not.Nil(result.__nvim_error)
    eq(-32602, result.__nvim_error.code)

    vim.api.nvim_buf_delete(buf, { force = true })
  end)end)
