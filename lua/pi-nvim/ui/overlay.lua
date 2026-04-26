-- pi-nvim UI overlay module
-- Floating window for sending selection to pi

local rpc = require('pi-nvim.rpc')
local session = require('pi-nvim.session')
local state = require('pi-nvim.state')
local input = require('pi-nvim.ui.input')
local layout = require('pi-nvim.ui.layout')

local M = {}

-- The overlay window
local overlay_win = nil
local overlay_buf = nil

-- Get visual selection or current line
local function get_selection()
  local mode = vim.fn.mode()

  if mode == 'v' or mode == 'V' or mode == '\x16' then -- visual, V-line, V-block
    -- Get visual selection
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")

    local lines = vim.api.nvim_buf_get_lines(0, start_pos[2] - 1, end_pos[2], false)

    -- Adjust last line if needed
    if #lines > 0 and end_pos[3] < #lines[#lines] then
      lines[#lines] = string.sub(lines[#lines], 1, end_pos[3])
    end

    -- Get file path and line range
    local file_path = vim.fn.fnamemodify(vim.fn.bufname('%'), ':~:.')
    local start_line = start_pos[2]
    local end_line = end_pos[2]

    return {
      text = table.concat(lines, '\n'),
      file_path = file_path,
      start_line = start_line,
      end_line = end_line,
    }
  else
    -- Normal mode: get current line
    local line_num = vim.fn.line('.')
    local lines = vim.api.nvim_buf_get_lines(0, line_num - 1, line_num, false)

    return {
      text = lines[1] or '',
      file_path = vim.fn.fnamemodify(vim.fn.bufname('%'), ':~:.'),
      start_line = line_num,
      end_line = line_num,
    }
  end
end

-- Format selection as fenced code block
local function format_selection(selection)
  local file_ref = selection.file_path

  if selection.start_line ~= selection.end_line then
    file_ref = selection.file_path .. ':' .. selection.start_line .. '-' .. selection.end_line
  elseif selection.start_line > 0 then
    file_ref = selection.file_path .. ':' .. selection.start_line
  end

  local blocks = {
    '```' .. file_ref,
    selection.text,
    '```',
    '',
    -- User types instructions below
  }

  return table.concat(blocks, '\n')
end

-- Create the overlay
function M.send_selection()
  -- Get the selection
  local selection = get_selection()

  if selection.text == '' then
    vim.notify('[pi-nvim] No selection to send', vim.log.levels.WARN)
    return
  end

  -- Check if pi panel is visible
  if state.layout_state == 'split' or state.layout_state == 'fullscreen' then
    -- Pi is visible - pre-fill input buffer and focus it
    local formatted = format_selection(selection)
    input.prefill(formatted)
    layout.focus_input()
    return
  end

  -- Pi is hidden - show floating overlay
  M.show_overlay(selection)
end

-- Show the floating overlay
function M.show_overlay(selection)
  -- Close existing overlay
  if overlay_win and vim.api.nvim_win_is_valid(overlay_win) then
    vim.api.nvim_win_close(overlay_win, true)
  end

  local width = math.floor(vim.o.columns * 0.6)
  local height = math.floor(vim.o.lines * 0.4)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- Create buffer
  overlay_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(overlay_buf, 'bufhidden', 'hide')
  vim.api.nvim_buf_set_option(overlay_buf, 'filetype', 'markdown')

  -- Set content
  local content = format_selection(selection)
  vim.api.nvim_buf_set_lines(overlay_buf, 0, -1, false, vim.split(content, '\n'))

  -- Create window
  local opts = {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    title = { { text = ' pi ', highlight = 'Title' } },
  }

  overlay_win = vim.api.nvim_open_win(overlay_buf, true, opts)

  -- Disable various features
  vim.api.nvim_win_set_option(overlay_win, 'number', false)
  vim.api.nvim_win_set_option(overlay_win, 'relativenumber', false)
  vim.api.nvim_win_set_option(overlay_win, 'cursorline', false)
  vim.api.nvim_win_set_option(overlay_win, 'wrap', true)

  -- Add help text at bottom
  local help_lines = { '', '---', '<CR> send  <Esc> cancel  <S-CR> new line' }
  local buf_line_count = vim.api.nvim_buf_line_count(overlay_buf)
  vim.api.nvim_buf_set_lines(overlay_buf, buf_line_count, buf_line_count, false, help_lines)

  -- Setup keybindings
  vim.keymap.set('n', '<CR>', function()
    M.send_from_overlay()
  end, { silent = true, buffer = overlay_buf })

  vim.keymap.set('i', '<CR>', function()
    M.send_from_overlay()
  end, { silent = true, buffer = overlay_buf })

  vim.keymap.set('n', '<Esc>', function()
    M.close_overlay()
  end, { silent = true, buffer = overlay_buf })

  vim.keymap.set('i', '<Esc>', function()
    M.close_overlay()
  end, { silent = true, buffer = overlay_buf })

  vim.keymap.set('i', '<S-CR>', function()
    vim.api.nvim_put({ '' }, 'i', true, true)
  end, { silent = true, buffer = overlay_buf })

  -- Enter insert mode
  -- Find where user text starts (after the ```block)
  local line_count = vim.api.nvim_buf_line_count(overlay_buf)
  vim.api.nvim_win_set_cursor(overlay_win, { line_count - 3, 0 })
  vim.cmd('startinsert')
end

-- Close the overlay
function M.close_overlay()
  if overlay_win and vim.api.nvim_win_is_valid(overlay_win) then
    vim.api.nvim_win_close(overlay_win, true)
  end
  overlay_win = nil
  overlay_buf = nil
end

-- Send from overlay
function M.send_from_overlay()
  local bufnr = overlay_buf
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local message = table.concat(lines, '\n')

  -- Close overlay first
  M.close_overlay()

  -- Ensure pi is started
  if not session.ensure_started() then
    return
  end

  -- If streaming, show indicator
  if state.streaming then
    vim.notify('⏳ pi is working — message will be queued', vim.log.levels.INFO)
  else
    vim.notify('✓ sent to pi', vim.log.levels.INFO)
  end

  -- Send the message
  if state.streaming then
    rpc.steer(message)
  else
    rpc.prompt(message)
  end
end

return M