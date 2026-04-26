-- pi-nvim state module
-- Shared state for streaming status, messages, model info, session data, connection status

local M = {
  -- Connection state
  connected = false,           -- pi RPC process is running
  disconnected_reason = nil,  -- why we disconnected (crash, manual, etc.)

  -- Streaming state
  streaming = false,            -- agent is currently streaming a response
  thinking = false,            -- agent is thinking (between turns)
  is_compacting = false,       -- compaction in progress

  -- Session state
  session_id = nil,            -- current session ID
  session_file = nil,          -- path to session file
  session_name = nil,          -- user-set session name

  -- Model state
  model = nil,                 -- current model info { id, name, provider }
  thinking_level = 'medium',   -- current thinking level

  -- Message state
  messages = {},               -- conversation history
  pending_steering = {},       -- queued steering messages
  pending_followup = {},       -- queued follow-up messages

  -- UI state
  layout_state = 'hidden',      -- 'hidden', 'split', 'fullscreen'
  pi_win = nil,                -- pi panel window ID
  chat_buf = nil,              -- chat buffer number
  input_buf = nil,             -- input buffer number

  -- Diff decoration tracking
  diff_decorations = {},       -- { [buffer_number]: { extmarks: {}, cleanup_fn: fn } }

  -- Agent stats
  tokens_in = 0,
  tokens_out = 0,
  total_cost = 0,

  -- Event callbacks (set by init.lua)
  on_agent_start = nil,
  on_agent_end = nil,
  on_message = nil,
  on_tool_start = nil,
  on_tool_end = nil,
  on_error = nil,
  on_queue_update = nil,
}

function M.reset()
  M.connected = false
  M.disconnected_reason = nil
  M.streaming = false
  M.thinking = false
  M.is_compacting = false
  -- Don't reset session_id/file - might want to resume
  -- Don't reset model - might want to keep same model
  M.messages = {}
  M.pending_steering = {}
  M.pending_followup = {}
  M.diff_decorations = {}
end

function M.set_connected(connected)
  M.connected = connected
  if not connected then
    M.streaming = false
    M.thinking = false
  end
end

function M.set_streaming(streaming)
  M.streaming = streaming
end

function M.set_thinking(thinking)
  M.thinking = thinking
end

function M.set_model(model_info)
  M.model = model_info
end

function M.add_message(msg)
  table.insert(M.messages, msg)
end

function M.add_steering(msg)
  table.insert(M.pending_steering, msg)
end

function M.add_followup(msg)
  table.insert(M.pending_followup, msg)
end

function M.clear_queue()
  M.pending_steering = {}
  M.pending_followup = {}
end

function M.set_layout(state)
  M.layout_state = state
end

function M.track_diff_buffer(bufnr, cleanup_fn)
  M.diff_decorations[bufnr] = { cleanup_fn = cleanup_fn }
end

function M.clear_diff_buffer(bufnr)
  M.diff_decorations[bufnr] = nil
end

function M.clear_all_diffs()
  for bufnr, _ in pairs(M.diff_decorations) do
    if M.diff_decorations[bufnr] and M.diff_decorations[bufnr].cleanup_fn then
      M.diff_decorations[bufnr].cleanup_fn()
    end
    M.diff_decorations[bufnr] = nil
  end
end

function M.update_from_state(state_data)
  -- Update state from get_state RPC response
  if state_data.model then
    M.model = state_data.model
  end
  if state_data.thinkingLevel then
    M.thinking_level = state_data.thinkingLevel
  end
  if state_data.isStreaming ~= nil then
    M.streaming = state_data.isStreaming
  end
  if state_data.isCompacting ~= nil then
    M.is_compacting = state_data.isCompacting
  end
  if state_data.sessionFile then
    M.session_file = state_data.sessionFile
  end
  if state_data.sessionId then
    M.session_id = state_data.sessionId
  end
  if state_data.sessionName then
    M.session_name = state_data.sessionName
  end
  if state_data.messageCount then
    M.message_count = state_data.messageCount
  end
  if state_data.pendingMessageCount then
    M.pending_message_count = state_data.pendingMessageCount
  end
end

function M.get_model_display()
  if M.model and M.model.name then
    return M.model.name
  end
  return 'unknown'
end

function M.is_active()
  return M.connected and (M.streaming or M.thinking)
end

return M