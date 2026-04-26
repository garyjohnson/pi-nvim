-- pi-nvim UI layout module
-- Manages window layout: split toggle, fullscreen toggle, adaptive vertical/horizontal

local state = require('pi-nvim.state')
local config = require('pi-nvim.config')
local chat = require('pi-nvim.ui.chat')
local input = require('pi-nvim.ui.input')
local diff = require('pi-nvim.ui.diff')
local status = require('pi-nvim.ui.status')

local M = {}

-- Get split dimensions based on config and screen size
local function get_split_dims()
  local cfg = config.get()
  local columns = vim.o.columns
  local lines = vim.o.lines

  if cfg.layout == 'vertical' then
    return 'vertical', cfg.split_width
  elseif cfg.layout == 'horizontal' then
    return 'horizontal', cfg.split_height
  else -- adaptive
    if columns >= lines * 2 then
      return 'vertical', cfg.split_width
    else
      return 'horizontal', cfg.split_height
    end
  end
end

-- Create the pi panel (chat + input buffers)
function M.create_panel()
  -- If already exists, just show it
  if state.chat_buf and state.input_buf then
    return state.chat_buf, state.input_buf
  end

  local orientation, size = get_split_dims()

  -- Create chat buffer (read-only)
  state.chat_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(state.chat_buf, 'pi-chat')
  vim.api.nvim_buf_set_option(state.chat_buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(state.chat_buf, 'bufhidden', 'hide')
  vim.api.nvim_buf_set_option(state.chat_buf, 'modifiable', false)
  vim.api.nvim_buf_set_option(state.chat_buf, 'filetype', 'markdown')

  -- Create input buffer (editable)
  state.input_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(state.input_buf, 'pi-input')
  vim.api.nvim_buf_set_option(state.input_buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(state.input_buf, 'bufhidden', 'hide')
  vim.api.nvim_buf_set_option(state.input_buf, 'modifiable', true)

  -- Setup input buffer keymaps
  input.setup_buffer(state.input_buf)

  -- Create the split
  local origin_win = vim.api.nvim_get_current_win()
  local origin_buf = vim.api.nvim_get_current_buf()

  if orientation == 'vertical' then
    vim.cmd('leftabove ' .. size .. 'vsplit')
  else
    vim.cmd('topright ' .. size .. 'split')
  end

  state.pi_win = vim.api.nvim_get_current_win()

  -- Set chat buffer in the new window
  vim.api.nvim_win_set_buf(state.pi_win, state.chat_buf)

  -- Disable numbers, sign column, fold column in pi window
  vim.api.nvim_win_set_option(state.pi_win, 'number', false)
  vim.api.nvim_win_set_option(state.pi_win, 'relativenumber', false)
  vim.api.nvim_win_set_option(state.pi_win, 'signcolumn', 'no')
  vim.api.nvim_win_set_option(state.pi_win, 'foldcolumn', '0')

  -- Create input area below chat
  vim.cmd('belowright new')
  local input_win = vim.api.nvim_get_current_win()

  -- Set input buffer in input window
  vim.api.nvim_win_set_buf(input_win, state.input_buf)

  -- Disable various features in input window
  vim.api.nvim_win_set_option(input_win, 'number', false)
  vim.api.nvim_win_set_option(input_win, 'relativenumber', false)
  vim.api.nvim_win_set_option(input_win, 'signcolumn', 'no')
  vim.api.nvim_win_set_option(input_win, 'foldcolumn', '0')
  vim.api.nvim_win_set_option(input_win, 'wrap', true)

  -- Set window layout
  -- Top: chat, Bottom: input
  -- We need to make them equal height
  vim.cmd('wincmd J') -- Join windows, makes current the bottom
  if orientation == 'vertical' then
    vim.cmd('wincmd H') -- Join windows, makes current the left
  end

  -- Store window IDs
  state.chat_win = state.pi_win
  state.input_win = input_win

  -- Go back to original window
  vim.api.nvim_set_current_win(origin_win)

  -- Setup status line for pi windows
  status.setup_pi_statusline(state.chat_win)
  status.setup_pi_statusline(state.input_win)

  -- Initial render
  chat.clear()
  chat.render_header()

  return state.chat_buf, state.input_buf
end

-- Open the pi panel in split view
function M.open_split()
  if state.layout_state == 'split' or state.layout_state == 'fullscreen' then
    return
  end

  M.create_panel()
  state.set_layout('split')
end

-- Toggle split on/off
function M.toggle_split()
  if state.layout_state == 'split' then
    M.close_panel()
  elseif state.layout_state == 'fullscreen' then
    M.show_split()
  else
    M.open_split()
  end
end

-- Show split from fullscreen
function M.show_split()
  if state.layout_state ~= 'fullscreen' then
    return
  end

  -- Just show the split layout
  -- Fullscreen was achieved by closing splits, so re-open them
  if not state.chat_buf then
    M.create_panel()
  end

  state.set_layout('split')
end

-- Toggle fullscreen
function M.toggle_fullscreen()
  if state.layout_state == 'fullscreen' then
    -- Return to split
    M.show_split()
  else
    -- Go fullscreen
    M.close_panel()
    M.create_panel()
    state.set_layout('fullscreen')
  end
end

-- Close the pi panel
function M.close_panel()
  if state.chat_win and vim.api.nvim_win_is_valid(state.chat_win) then
    vim.api.nvim_win_close(state.chat_win, true)
  end
  if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
    vim.api.nvim_win_close(state.input_win, true)
  end

  state.chat_win = nil
  state.input_win = nil
  state.pi_win = nil

  -- Note: buffers persist, just hide the windows
  state.set_layout('hidden')
end

-- Focus the input buffer
function M.focus_input()
  if state.layout_state == 'hidden' then
    M.open_split()
  end

  if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
    vim.api.nvim_set_current_win(state.input_win)
    -- Enter insert mode
    vim.cmd('startinsert')
  end
end

-- Focus the chat buffer (read-only)
function M.focus_chat()
  if state.layout_state == 'hidden' then
    M.open_split()
  end

  if state.chat_win and vim.api.nvim_win_is_valid(state.chat_win) then
    vim.api.nvim_set_current_win(state.chat_win)
  end
end

-- Jump back to previous window (from input buffer)
function M.jump_back()
  vim.cmd('wincmd p')
end

return M