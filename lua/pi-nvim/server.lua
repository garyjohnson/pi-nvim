--- Unix domain socket server for pi-nvim.
--- Listens on a socket file, accepts one client connection,
--- and dispatches JSON-RPC 2.0 requests to registered handlers.
local M = {}

local uv = vim.loop

-- Server state
local server = nil
local client = nil
local sock_path = nil
local buffer = ""

-- Handler registry: method_name -> function(params) -> result
local handlers = {}

-- Logger
local log_level = vim.log.levels.INFO
local log_file = nil

--- Log a message at the given level.
---@param level integer vim.log.levels value
---@param msg string
local function log(level, msg)
  if level < log_level then
    return
  end
  local level_name = vim.log.levels[level] or "UNKNOWN"
  -- Remove the "TRACE" etc prefix since vim.log.levels values are numbers
  for name, val in pairs(vim.log.levels) do
    if type(val) == "number" and val == level then
      level_name = name
      break
    end
  end
  local timestamp = os.date("!%Y-%m-%dT%H:%M:%S")
  local line = string.format("%s [%s] %s\n", timestamp, level_name, msg)
  if log_file then
    local fd = io.open(log_file, "a")
    if fd then
      fd:write(line)
      fd:close()
    end
  end
  if level >= vim.log.levels.WARN then
    vim.schedule(function()
      vim.notify(string.format("[pi-nvim] %s", msg), level)
    end)
  end
end

--- Parse and dispatch a single JSON-RPC message.
---@param data string A complete JSON-RPC message (one line)
local function dispatch(data)
  local ok, msg = pcall(vim.json.decode, data)
  if not ok or type(msg) ~= "table" then
    log(vim.log.levels.ERROR, string.format("Failed to parse JSON: %s", data))
    M.send_error(nil, -32700, "Parse error")
    return
  end

  -- Validate basic JSON-RPC structure
  if msg.jsonrpc ~= "2.0" then
    M.send_error(msg.id, -32600, "Invalid request: missing or wrong jsonrpc version")
    return
  end

  -- Notifications (no id) are accepted but we have none in v1
  if msg.id == nil and msg.method then
    log(vim.log.levels.DEBUG, string.format("Received notification: %s", msg.method))
    return
  end

  -- Request (has id and method)
  if msg.method then
    local handler = handlers[msg.method]
    if not handler then
      log(vim.log.levels.WARN, string.format("Unknown method: %s", msg.method))
      M.send_error(msg.id, -32601, string.format("Method not found: %s", msg.method))
      return
    end

    local params = msg.params or {}
    local request_id = msg.id

    -- Schedule handler to run in main Neovim event loop to avoid
    -- "fast event context" errors when calling nvim_list_bufs,
    -- nvim_get_mode, and other APIs that aren't allowed in callbacks.
    vim.schedule(function()
      local ok_handler, result = pcall(handler, params)
      if not ok_handler then
        log(vim.log.levels.ERROR, string.format("Handler error for %s: %s", msg.method, result))
        M.send_error(request_id, -32603, string.format("Internal error: %s", result))
        return
      end

      -- Handler may return (result, error) where error is a table {code, message}
      if type(result) == "table" and result.__nvim_error then
        local err = result.__nvim_error
        M.send_error(request_id, err.code, err.message)
      else
        M.send_result(request_id, result)
      end
    end)
  else
    M.send_error(msg.id, -32600, "Invalid request: no method")
  end
end

--- Process the line buffer, dispatching complete messages.
local function process_buffer()
  while true do
    local idx = string.find(buffer, "\n")
    if not idx then
      break
    end
    local line = string.sub(buffer, 1, idx - 1)
    buffer = string.sub(buffer, idx + 1)
    if #line > 0 then
      log(vim.log.levels.DEBUG, string.format("Received: %s", line))
      dispatch(line)
    end
  end
end

--- Send a JSON-RPC response to the client.
---@param id integer|string|nil Request ID
---@param result table The result value
function M.send_result(id, result)
  if not client or client:is_closing() then
    return
  end
  local response = vim.json.encode({
    jsonrpc = "2.0",
    id = id,
    result = result,
  })
  log(vim.log.levels.DEBUG, string.format("Sending: %s", response))
  client:write(response .. "\n")
end

--- Send a JSON-RPC error response to the client.
---@param id integer|string|nil Request ID
---@param code integer Error code
---@param message string Error message
function M.send_error(id, code, message)
  if not client or client:is_closing() then
    return
  end
  local response = vim.json.encode({
    jsonrpc = "2.0",
    id = id,
    error = { code = code, message = message },
  })
  log(vim.log.levels.DEBUG, string.format("Sending error: %s", response))
  client:write(response .. "\n")
end

--- Send a JSON-RPC notification to the client.
---@param method string
---@param params table
function M.send_notification(method, params)
  if not client or client:is_closing() then
    return
  end
  local notification = vim.json.encode({
    jsonrpc = "2.0",
    method = method,
    params = params or {},
  })
  log(vim.log.levels.DEBUG, string.format("Sending notification: %s", notification))
  client:write(notification .. "\n")
end

--- Register a handler for a JSON-RPC method.
---@param method string Method name
---@param handler function(params: table) -> result_table
function M.register_method(method, handler)
  handlers[method] = handler
end

--- Start the unix domain socket server.
---@param opts? table Optional: { log_level }
---@return string sock_path The socket path clients should connect to
function M.start(opts)
  opts = opts or {}

  -- Configure logging
  log_level = opts.log_level or vim.log.levels.INFO
  log_file = vim.fn.stdpath("log") .. "/pi-nvim.log"

  -- Create socket path
  local pid = vim.fn.getpid()
  sock_path = string.format("/tmp/pi-nvim-%d.sock", pid)

  -- Remove stale socket if it exists
  vim.fn.delete(sock_path)

  -- Create a pipe handle for unix domain socket
  server = uv.new_pipe(false)

  local bind_ok, bind_err = pcall(function()
    server:bind(sock_path)
  end)
  if not bind_ok then
    log(vim.log.levels.ERROR, string.format("Failed to bind socket: %s", bind_err))
    server:close()
    server = nil
    return nil
  end

  -- Restrict socket permissions to owner only (rw-------)
  -- to prevent other users on the same machine from connecting.
  -- Unix domain sockets honor filesystem permissions.
  vim.fn.setfperm(sock_path, "rw-------")

  local listen_ok, listen_err = pcall(function()
    server:listen(128, function(on_complete)
      if on_complete then
        log(vim.log.levels.ERROR, string.format("Connection accept error: %s", vim.inspect(on_complete)))
        return
      end

      -- Close existing client if any (v1: single client)
      if client and not client:is_closing() then
        client:close()
      end

      client = uv.new_pipe(false)
      server:accept(client)
      log(vim.log.levels.INFO, "Client connected")

      buffer = ""

      client:read_start(function(err, data)
        if err then
          log(vim.log.levels.ERROR, string.format("Read error: %s", err))
          client:close()
          client = nil
          return
        end
        if data then
          buffer = buffer .. data
          process_buffer()
        else
          -- EOF: client disconnected
          log(vim.log.levels.INFO, "Client disconnected")
          client:close()
          client = nil
        end
      end)
    end)
  end)

  if not listen_ok then
    log(vim.log.levels.ERROR, string.format("Failed to listen on socket: %s", listen_err))
    server:close()
    server = nil
    vim.fn.delete(sock_path)
    sock_path = nil
    return nil
  end

  log(vim.log.levels.INFO, string.format("Socket server started on %s", sock_path))
  return sock_path
end

--- Stop the server and clean up.
function M.stop()
  if client and not client:is_closing() then
    client:close()
  end
  client = nil

  if server and not server:is_closing() then
    server:close()
  end
  server = nil

  if sock_path then
    vim.fn.delete(sock_path)
    log(vim.log.levels.INFO, string.format("Socket removed: %s", sock_path))
    sock_path = nil
  end
end

--- Get the current socket path.
---@return string|nil
function M.get_sock_path()
  return sock_path
end

--- Check if the server is running.
---@return boolean
function M.is_running()
  return server ~= nil and not server:is_closing()
end

--- Check if a client is connected.
---@return boolean
function M.is_client_connected()
  return client ~= nil and not client:is_closing()
end

--- Create a handler error result that dispatch() recognizes.
---@param code integer
---@param message string
---@return table
function M.error_result(code, message)
  return { __nvim_error = { code = code, message = message } }
end

return M