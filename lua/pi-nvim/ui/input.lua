-- pi-nvim UI input module
-- Handles prompt composition and sending in the input buffer

local rpc = require('pi-nvim.rpc')
local state = require('pi-nvim.state')
local config = require('pi-nvim.config')
local session = require('pi-nvim.session')
local chat = require('pi-nvim.ui.chat')
local diff = require('pi-nvim.ui.diff')

local M = {}

-- Get the input buffer
function M.get_buf()
  return state.input_buf
end

-- Setup the input buffer with keybindings
function M.setup_buffer(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local cfg = config.get()

  -- Keybindings in insert mode
  local function send_prompt()
    M.send()
  end

  local function new_line()
    -- Insert newline
    vim.api.nvim_put({ '' }, 'i', true, true)
  end

  local function jump_back()
    require('pi-nvim.ui.layout').jump_back()
  end

  local function clear_input()
    M.clear_input()
  end

  -- CR to send
  vim.keymap.set('i', cfg.send_key, send_prompt, { buffer = bufnr, silent = true, nowait = true })

  -- S-CR for newline
  vim.keymap.set('i', '<S-CR>', new_line, { buffer = bufnr, silent = true, nowait = true })

  -- Fallback for terminals without S-CR support
  vim.keymap.set('i', '<C-CR>', new_line, { buffer = bufnr, silent = true, nowait = true })

  -- Esc to jump back
  vim.keymap.set('i', '<Esc>', jump_back, { buffer = bufnr, silent = true, nowait = true })

  -- C-C to clear input
  vim.keymap.set('i', '<C-C>', clear_input, { buffer = bufnr, silent = true, nowait = true })

  -- Optional: auto-enter insert mode on focus
  if cfg.input_autoinsert then
    -- Could use BufWinEnter autocmd
  end
end

-- Get input from buffer
function M.get_input()
  local bufnr = state.input_buf
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return ''
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return table.concat(lines, '\n')
end

-- Clear input buffer
function M.clear_input()
  local bufnr = state.input_buf
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
end

-- Send prompt (called by CR keybinding)
function M.send()
  local message = M.get_input()
  if message == '' or not message:match('%S') then
    return
  end

  -- Check for auto-save
  local cfg = config.get()
  if cfg.auto_save ~= 'never' then
    local modified = vim.fn.bufnr('%s') -- Get all buffers
    local has_modified = false
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_option(buf, 'modified') then
        has_modified = true
        break
      end
    end

    if has_modified then
      if cfg.auto_save == 'ask' then
        vim.ui.select({
          { desc = 'Yes, save all', value = 'save' },
          { desc = 'No, send anyway', value = 'nosave' },
          { desc = 'Cancel', value = 'cancel' },
        }, {
          prompt = 'You have unsaved buffers. Save before sending to pi?',
          format_item = function(item)
            return item.desc
          end,
        }, function(choice)
          if choice and choice.value == 'save' then
            vim.cmd('wall')
            M.do_send(message)
          elseif choice and choice.value == 'nosave' then
            M.do_send(message)
          end
          -- cancel: do nothing
        end)
        return
      elseif cfg.auto_save == 'always' then
        vim.cmd('wall')
      end
    end
  end

  M.do_send(message)
end

-- Actually send the message
function M.do_send(message)
  -- Clear input
  M.clear_input()

  -- Ensure pi is started
  if not session.ensure_started() then
    return
  end

  -- If streaming, send as steer; otherwise normal prompt
  if state.streaming then
    rpc.steer(message)
    vim.notify('✓ message queued (pi is working)', vim.log.levels.INFO)
  else
    rpc.prompt(message)
  end
end

-- Send steering message manually
function M.steer()
  local message = M.get_input()
  if message == '' then
    return
  end

  M.clear_input()

  if not session.ensure_started() then
    return
  end

  rpc.steer(message)
end

-- Send follow-up message
function M.send_followup()
  local message = M.get_input()
  -- If no input, could use last assistant text, but for now require input
  if message == '' then
    vim.ui.input({ prompt = 'Follow-up message:' }, function(input)
      if input and input ~= '' then
        if not session.ensure_started() then
          return
        end
        rpc.follow_up(input)
      end
    end)
  else
    M.clear_input()

    if not session.ensure_started() then
      return
    end

    rpc.follow_up(message)
  end
end

-- Pre-fill input buffer with text
function M.prefill(text)
  local bufnr = state.input_buf
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local lines = {}
  for line in text:gmatch('[^\n]+') do
    table.insert(lines, line)
  end

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  -- Jump to end
  local line_count = #lines
  vim.api.nvim_buf_set_cursor(bufnr, { line_count, 0 })
end

return M