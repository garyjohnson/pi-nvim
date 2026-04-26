-- pi-nvim UI chat module
-- Renders conversation history in the chat buffer

local state = require('pi-nvim.state')

local M = {}

-- Get the chat buffer
function M.get_buf()
  return state.chat_buf
end

-- Clear the chat buffer
function M.clear()
  local buf = state.chat_buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
  vim.api.nvim_buf_set_option(buf, 'modifiable', true)

  -- Clear virtual texts
  vim.api.nvim_buf_clear_namespace(buf, -1, 0, -1)
end

-- Render header with session info
function M.render_header()
  local buf = state.chat_buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local lines = {
    '# pi',
    '',
  }

  if state.model and state.model.name then
    table.insert(lines, 'Model: ' .. state.model.name)
  else
    table.insert(lines, 'Model: (none)')
  end

  table.insert(lines, '')
  table.insert(lines, '---')
  table.insert(lines, '')

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
end

-- Render a single message
function M.render_message(msg)
  local buf = state.chat_buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  vim.api.nvim_buf_set_option(buf, 'modifiable', true)

  local lines = {}
  local content = msg.content

  if type(content) == 'table' then
    for _, block in ipairs(content) do
      if block.type == 'text' then
        local text = block.text or ''
        for line in text:gmatch('[^\n]+') do
          table.insert(lines, line)
        end
      elseif block.type == 'toolCall' then
        table.insert(lines, '')
        table.insert(lines, '▶ ' .. block.name)
        if block.arguments then
          local args_str = type(block.arguments) == 'string'
            and block.arguments
            or vim.json.encode(block.arguments)
          for line in args_str:gmatch('[^\n]+') do
            table.insert(lines, '  ' .. line)
          end
        end
      elseif block.type == 'thinking' then
        table.insert(lines, '[thinking]')
      end
    end
  elseif type(content) == 'string' then
    for line in content:gmatch('[^\n]+') do
      table.insert(lines, line)
    end
  end

  -- Prefix based on role
  local prefix = '>'
  if msg.role == 'assistant' then
    prefix = ''
  elseif msg.role == 'toolResult' then
    prefix = '│ '
  end

  -- Insert at end
  local start_row = vim.api.nvim_buf_line_count(buf)
  local prefixed_lines = {}
  for i, line in ipairs(lines) do
    if i == 1 then
      table.insert(prefixed_lines, prefix .. line)
    else
      table.insert(prefixed_lines, '  ' .. line)
    end
  end

  vim.api.nvim_buf_set_lines(buf, start_row, start_row, false, prefixed_lines)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)

  -- Scroll to bottom
  if state.chat_win and vim.api.nvim_win_is_valid(state.chat_win) then
    vim.api.nvim_win_set_cursor(state.chat_win, { start_row + #lines, 0 })
  end
end

-- Append text to last assistant message (streaming)
function M.append_text(delta)
  local buf = state.chat_buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  -- For now, just append as raw text
  -- A fuller implementation would apply markdown highlighting
  vim.api.nvim_buf_set_option(buf, 'modifiable', true)

  local line_count = vim.api.nvim_buf_line_count(buf)
  local lines = {}

  for line in (delta.delta or ''):gmatch('[^\n]+') do
    table.insert(lines, line)
  end

  if #lines > 0 then
    vim.api.nvim_buf_set_lines(buf, line_count, line_count, false, lines)
  end

  vim.api.nvim_buf_set_option(buf, 'modifiable', false)

  -- Scroll to bottom
  if state.chat_win and vim.api.nvim_win_is_valid(state.chat_win) then
    local new_count = vim.api.nvim_buf_line_count(buf)
    vim.api.nvim_win_set_cursor(state.chat_win, { new_count, 0 })
  end
end

-- Finalize a message after streaming completes
function M.finalize_message(msg)
  -- For now, already handled by render_message during streaming
  -- Could apply final markdown highlighting here
end

-- Apply markdown highlighting to a range
function M.highlight_markdown(start_line, end_line)
  local buf = state.chat_buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  -- This is where treesitter or regex highlighting would be applied
  -- For MVP, skip and let text render as plain
end

return M