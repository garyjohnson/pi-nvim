-- pi-nvim RPC module
-- Spawns pi --mode rpc, sends commands, parses events

local state = require('pi-nvim.state')
local config = require('pi-nvim.config')

local M = {}

-- Job ID of the pi subprocess
local pi_job = nil

-- Buffer for incomplete JSON lines
local line_buffer = ''

-- Request tracking
local pending_requests = {}
local request_id = 0

--- Parse a single JSONL line
local function parse_json_line(line)
  if line == '' or line == nil then
    return nil
  end
  local ok, data = pcall(vim.json.decode, line)
  if not ok then
    vim.notify('[pi-nvim] JSON parse error: ' .. tostring(data), vim.log.levels.ERROR)
    return nil
  end
  return data
end

--- Send a command to pi
local function send_command(cmd)
  if not pi_job or pi_job == 0 then
    vim.notify('[pi-nvim] pi process not running', vim.log.levels.WARN)
    return nil
  end

  local id = 'req_' .. (request_id + 1)
  request_id = request_id + 1

  local payload = vim.tbl_extend('force', cmd, { id = id })
  local line = vim.json.encode(payload)

  vim.fn.chansend(pi_job, line .. '\n')

  return id
end

--- Handle an RPC event
local function handle_event(data)
  local event_type = data.type

  if event_type == 'response' then
    -- Handle response to a command
    local req_id = data.id
    if req_id and pending_requests[req_id] then
      pending_requests[req_id](data)
      pending_requests[req_id] = nil
    end
    return
  end

  -- Handle agent events
  if event_type == 'agent_start' then
    state.set_streaming(true)
    if state.on_agent_start then
      state.on_agent_start()
    end

  elseif event_type == 'agent_end' then
    state.set_streaming(false)
    if state.on_agent_end then
      state.on_agent_end(data.messages)
    end

  elseif event_type == 'turn_start' then
    state.set_thinking(true)

  elseif event_type == 'turn_end' then
    state.set_thinking(false)

  elseif event_type == 'message_start' then
    if state.on_message then
      state.on_message('start', data.message)
    end

  elseif event_type == 'message_update' then
    if state.on_message then
      state.on_message('update', data.message, data.assistantMessageEvent)
    end

  elseif event_type == 'message_end' then
    if state.on_message then
      state.on_message('end', data.message)
    end

  elseif event_type == 'tool_execution_start' then
    if state.on_tool_start then
      state.on_tool_start(data.toolCallId, data.toolName, data.args)
    end

  elseif event_type == 'tool_execution_update' then
    if state.on_tool_start then
      state.on_tool_start(data.toolCallId, data.toolName, data.args, data.partialResult)
    end

  elseif event_type == 'tool_execution_end' then
    if state.on_tool_end then
      state.on_tool_end(data.toolCallId, data.toolName, data.result, data.isError)
    end

  elseif event_type == 'queue_update' then
    state.pending_steering = data.steering or {}
    state.pending_followup = data.followUp or {}
    if state.on_queue_update then
      state.on_queue_update(data.steering, data.followUp)
    end

  elseif event_type == 'compaction_start' then
    state.is_compacting = true

  elseif event_type == 'compaction_end' then
    state.is_compacting = false

  elseif event_type == 'extension_error' then
    vim.notify('[pi-nvim] Extension error: ' .. data.error, vim.log.levels.ERROR)
    if state.on_error then
      state.on_error('extension', data.error)
    end

  elseif event_type == 'extension_ui_request' then
    M.handle_extension_ui(data)

  end
end

--- Handle stdout data from pi
local function on_stdout(_, data, _)
  if not data or #data == 0 then
    return
  end

  for _, line in ipairs(data) do
    -- Handle line continuations
    if line_buffer ~= '' then
      line = line_buffer .. line
      line_buffer = ''
    end

    -- Check for incomplete JSON
    local count = 0
    for _ in line:gmatch('\n') do count = count + 1 end

    if count == 0 and not line:match('^%s*{') then
      -- Partial line
      line_buffer = line
    else
      -- Handle multiple JSONL entries in one chunk
      for sub_line in line:gmatch('[^\n]+') do
        if sub_line:match('^%s*{') then
          local event = parse_json_line(sub_line)
          if event then
            handle_event(event)
          end
        end
      end
    end
  end
end

--- Handle stderr from pi (log it)
local function on_stderr(_, data, _)
  if not data or #data == 0 then
    return
  end
  for _, line in ipairs(data) do
    if line and line ~= '' then
      vim.notify('[pi-nvim] ' .. line, vim.log.levels.DEBUG)
    end
  end
end

--- Handle pi process exit
local function on_exit(_, code, _)
  local was_connected = state.connected

  state.set_connected(false)
  state.set_streaming(false)

  if code ~= 0 and was_connected then
    state.disconnected_reason = 'crashed (exit code ' .. code .. ')'
    vim.notify('[pi-nvim] pi process exited with code ' .. code, vim.log.levels.ERROR)
    if state.on_error then
      state.on_error('crash', 'pi process exited with code ' .. code)
    end
  elseif was_connected then
    state.disconnected_reason = 'stopped'
    vim.notify('[pi-nvim] pi process stopped', vim.log.levels.INFO)
  end
end

--- Start the pi subprocess
function M.start(cwd)
  if pi_job and pi_job > 0 then
    return true -- Already running
  end

  local work_dir = cwd or vim.fn.getcwd()

  -- Build pi command
  local pi_cmd = { 'pi', '--mode', 'rpc', '--no-session' }

  -- Spawn the process
  pi_job = vim.fn.jobstart(pi_cmd, {
    cwd = work_dir,
    on_stdout = on_stdout,
    on_stderr = on_stderr,
    on_exit = on_exit,
    env = {
      -- Pass through relevant env vars
      ANTHROPIC_API_KEY = os.getenv('ANTHROPIC_API_KEY') or '',
      OPENAI_API_KEY = os.getenv('OPENAI_API_KEY') or '',
    },
  })

  if pi_job == 0 or pi_job == -1 then
    vim.notify('[pi-nvim] Failed to start pi process', vim.log.levels.ERROR)
    pi_job = nil
    return false
  end

  state.set_connected(true)
  state.disconnected_reason = nil

  -- Get initial state
  M.get_state()

  return true
end

--- Stop the pi subprocess
function M.stop()
  if not pi_job or pi_job == 0 then
    return
  end

  -- Try graceful abort first
  M.abort()

  -- Wait briefly then kill
  vim.defer_fn(function()
    if pi_job and pi_job > 0 then
      vim.fn.jobstop(pi_job)
    end
    pi_job = nil
    state.set_connected(false)
  end, 2000)
end

--- Get the job ID
function M.get_job()
  return pi_job
end

--- Send a prompt
function M.prompt(message, streaming_behavior)
  local cmd = {
    type = 'prompt',
    message = message,
  }

  if streaming_behavior then
    cmd.streamingBehavior = streaming_behavior
  end

  return send_command(cmd)
end

--- Send a steering message (delivered after current tool execution)
function M.steer(message)
  return send_command({
    type = 'steer',
    message = message,
  })
end

--- Send a follow-up message (delivered after agent finishes)
function M.follow_up(message)
  return send_command({
    type = 'follow_up',
    message = message,
  })
end

--- Abort current operation
function M.abort()
  return send_command({
    type = 'abort',
  })
end

--- Get current state
function M.get_state()
  return send_command({
    type = 'get_state',
  })
end

--- Get all messages
function M.get_messages()
  return send_command({
    type = 'get_messages',
  })
end

--- Get available models
function M.get_available_models()
  return send_command({
    type = 'get_available_models',
  })
end

--- Set model
function M.set_model(provider, model_id)
  return send_command({
    type = 'set_model',
    provider = provider,
    modelId = model_id,
  })
end

--- Set thinking level
function M.set_thinking_level(level)
  return send_command({
    type = 'set_thinking_level',
    level = level,
  })
end

--- New session
function M.new_session()
  return send_command({
    type = 'new_session',
  })
end

--- Get session stats
function M.get_session_stats()
  return send_command({
    type = 'get_session_stats',
  })
end

--- Switch session
function M.switch_session(session_path)
  return send_command({
    type = 'switch_session',
    sessionPath = session_path,
  })
end

--- Handle extension UI requests (select/confirm/input/editor)
function M.handle_extension_ui(request)
  local method = request.method
  local id = request.id

  if method == 'select' then
    vim.ui.select(request.options, { prompt = request.title }, function(choice)
      if choice then
        M.respond_ui(id, { value = choice })
      else
        M.respond_ui(id, { cancelled = true })
      end
    end)

  elseif method == 'confirm' then
    vim.ui.confirm(request.message, {
      prompt = request.title or 'Confirm',
      ['y'] = true,
      ['n'] = false,
    }, function(confirmed)
      if confirmed ~= nil then
        M.respond_ui(id, { confirmed = confirmed })
      else
        M.respond_ui(id, { cancelled = true })
      end
    end)

  elseif method == 'input' then
    vim.ui.input({ prompt = request.title, default = request.placeholder }, function(value)
      if value then
        M.respond_ui(id, { value = value })
      else
        M.respond_ui(id, { cancelled = true })
      end
    end)

  elseif method == 'editor' then
    -- For editor, we need to open a buffer
    -- For now, just cancel with empty response
    M.respond_ui(id, { cancelled = true })

  elseif method == 'notify' then
    -- Fire-and-forget notifications
    local level = vim.log.levels.INFO
    if request.notifyType == 'warning' then
      level = vim.log.levels.WARN
    elseif request.notifyType == 'error' then
      level = vim.log.levels.ERROR
    end
    vim.notify(request.message, level)

  elseif method == 'setStatus' then
    -- Handled by status module
    -- Fire-and-forget

  elseif method == 'setWidget' then
    -- Handled by chat module
    -- Fire-and-forget

  elseif method == 'setTitle' then
    -- Could set vim.fnopard('title')
    -- Fire-and-forget

  elseif method == 'set_editor_text' then
    -- Fire-and-forget - would set input buffer text
  end
end

--- Respond to an extension UI request
function M.respond_ui(id, response)
  response.type = 'extension_ui_response'
  response.id = id
  local line = vim.json.encode(response)
  vim.fn.chansend(pi_job, line .. '\n')
end

return M