-- pi-nvim session module
-- Handles session lifecycle: start, stop, resume, new, shutdown

local rpc = require('pi-nvim.rpc')
local state = require('pi-nvim.state')
local config = require('pi-nvim.config')
local chat = require('pi-nvim.ui.chat')
local diff = require('pi-nvim.ui.diff')
local status = require('pi-nvim.ui.status')

local M = {}

-- Ensure pi is started, lazy start on first interaction
function M.ensure_started()
  if not state.connected then
    local cwd = vim.fn.getcwd()
    local ok = rpc.start(cwd)
    if not ok then
      vim.notify('[pi-nvim] Failed to start pi process', vim.log.levels.ERROR)
      return false
    end

    -- Register event handlers
    state.on_agent_start = function()
      status.update()
    end

    state.on_agent_end = function(messages)
      status.update()
    end

    state.on_message = function(event_type, message, delta)
      if event_type == 'start' then
        chat.render_message(message)
      elseif event_type == 'update' then
        chat.append_text(delta)
      elseif event_type == 'end' then
        chat.finalize_message(message)
      end
    end

    state.on_tool_start = function(tool_call_id, tool_name, args, partial)
      diff.track_changes({
        tool_call_id = tool_call_id,
        tool_name = tool_name,
        args = args,
        partial = partial,
      })
    end

    state.on_tool_end = function(tool_call_id, tool_name, result, is_error)
      diff.track_changes({
        tool_call_id = tool_call_id,
        tool_name = tool_name,
        result = result,
        is_error = is_error,
      })
    end

    state.on_error = function(error_type, message)
      vim.notify('[pi-nvim] Error: ' .. message, vim.log.levels.ERROR)
    end

    -- Wait briefly for initial state, then load messages
    vim.defer_fn(function()
      if state.connected then
        M.resync()
      end
    end, 500)
  end

  return state.connected
end

-- Try to resume a session
function M.resume()
  local config_data = config.get()

  if config_data.session_resume == 'new' then
    return M.new()
  end

  -- TODO: List recent sessions and show picker
  -- For now, just start a new session or continue
  if config_data.session_resume == 'continue' then
    -- pi will auto-resume if a session exists in cwd
  end

  -- Default: ask via vim.ui.select
  vim.ui.select({
    { desc = 'New session', value = 'new' },
    { desc = 'Continue recent', value = 'continue' },
  }, {
    prompt = 'Start pi session',
    format_item = function(item)
      return item.desc
    end,
  }, function(choice)
    if choice and choice.value == 'new' then
      M.new()
    else
      M.ensure_started()
    end
  end)
end

-- Create a new session
function M.new()
  if not M.ensure_started() then
    return
  end

  -- Stop any existing session first
  if state.connected then
    rpc.new_session()
  end

  -- Clear chat buffer
  chat.clear()

  -- Reset session state
  state.session_id = nil
  state.session_file = nil
  state.session_name = nil
  state.messages = {}

  -- Start fresh
  vim.notify('[pi-nvim] Started new session', vim.log.levels.INFO)
end

-- Restart after crash
function M.restart()
  -- Clear any diff decorations
  diff.clear_all()

  -- Stop current if any
  if state.connected then
    rpc.stop()
  end

  -- Clear state
  state.reset()

  -- Restart
  local cwd = vim.fn.getcwd()
  local ok = rpc.start(cwd)

  if ok then
    vim.notify('[pi-nvim] pi restarted', vim.log.levels.INFO)
  else
    vim.notify('[pi-nvim] Failed to restart pi', vim.log.levels.ERROR)
  end
end

-- Re-sync messages from pi (on VimResume or manually)
function M.resync()
  if not state.connected then
    return
  end

  rpc.get_messages(function(response)
    if response.success and response.data and response.data.messages then
      state.messages = response.data.messages
      -- Re-render chat
      chat.clear()
      for _, msg in ipairs(response.data.messages) do
        chat.render_message(msg)
      end
    end
  end)
end

-- Shutdown (VimLeavePre)
function M.shutdown()
  if state.connected then
    -- Send abort to stop any running operation
    rpc.abort()

    -- Wait briefly for graceful shutdown
    vim.defer_fn(function()
      rpc.stop()
      state.set_connected(false)
    end, 2000)
  end
end

return M