-- pi-nvim main entry point
-- This is the main module that users require()

local M = {}

function M.setup(user_config)
  -- Load and apply configuration
  local config = require('pi-nvim.config').setup(user_config)

  -- Define commands
  vim.api.nvim_create_user_command('PiToggle', function()
    require('pi-nvim.ui.layout').toggle_split()
  end, { desc = 'Toggle pi split view' })

  vim.api.nvim_create_user_command('PiFullscreen', function()
    require('pi-nvim.ui.layout').toggle_fullscreen()
  end, { desc = 'Toggle pi fullscreen' })

  vim.api.nvim_create_user_command('PiSendSelection', function()
    require('pi-nvim.ui.overlay').send_selection()
  end, { desc = 'Send selection to pi' })

  vim.api.nvim_create_user_command('PiNewSession', function()
    require('pi-nvim.session').new()
  end, { desc = 'Start new pi session' })

  vim.api.nvim_create_user_command('PiResume', function()
    require('pi-nvim.session').resume()
  end, { desc = 'Resume pi session' })

  vim.api.nvim_create_user_command('PiRestart', function()
    require('pi-nvim.session').restart()
  end, { desc = 'Restart pi process' })

  vim.api.nvim_create_user_command('PiAbort', function()
    require('pi-nvim.rpc').abort()
  end, { desc = 'Abort current pi operation' })

  vim.api.nvim_create_user_command('PiJumpInput', function()
    require('pi-nvim.ui.layout').focus_input()
  end, { desc = 'Jump to pi input buffer' })

  vim.api.nvim_create_user_command('PiJumpOutput', function()
    require('pi-nvim.ui.layout').focus_chat()
  end, { desc = 'Jump to pi chat buffer' })

  vim.api.nvim_create_user_command('PiDiffClear', function()
    require('pi-nvim.ui.diff').clear_all()
  end, { desc = 'Clear diff decorations' })

  vim.api.nvim_create_user_command('PiStatus', function()
    print(require('pi-nvim.ui.status').get_status_line())
  end, { desc = 'Show pi status' })

  vim.api.nvim_create_user_command('PiFollowUp', function()
    require('pi-nvim.ui.input').send_followup()
  end, { desc = 'Send follow-up message' })

  -- Define keybindings
  local keys = config.keys

  -- Toggle split
  vim.keymap.set('n', keys.toggle, function()
    require('pi-nvim.ui.layout').toggle_split()
  end, { desc = 'Toggle pi split view' })

  -- Toggle fullscreen
  vim.keymap.set('n', keys.fullscreen, function()
    require('pi-nvim.ui.layout').toggle_fullscreen()
  end, { desc = 'Toggle pi fullscreen' })

  -- Send selection
  vim.keymap.set('n', keys.send_selection, function()
    require('pi-nvim.ui.overlay').send_selection()
  end, { desc = 'Send selection to pi' })
  vim.keymap.set('x', keys.send_selection, function()
    require('pi-nvim.ui.overlay').send_selection()
  end, { desc = 'Send selection to pi' })

  -- New session
  vim.keymap.set('n', keys.new_session, function()
    require('pi-nvim.session').new()
  end, { desc = 'New pi session' })

  -- Resume session
  vim.keymap.set('n', keys.resume, function()
    require('pi-nvim.session').resume()
  end, { desc = 'Resume pi session' })

  -- Abort
  vim.keymap.set('n', keys.abort, function()
    require('pi-nvim.rpc').abort()
  end, { desc = 'Abort pi operation' })

  -- Jump to input
  vim.keymap.set('n', keys.jump_input, function()
    require('pi-nvim.ui.layout').focus_input()
  end, { desc = 'Jump to pi input' })

  -- Jump to chat
  vim.keymap.set('n', keys.jump_output, function()
    require('pi-nvim.ui.layout').focus_chat()
  end, { desc = 'Jump to pi output' })

  -- Clear diffs
  vim.keymap.set('n', keys.clear_diffs, function()
    require('pi-nvim.ui.diff').clear_all()
  end, { desc = 'Clear diff decorations' })

  -- Autocmds
  local augroup = vim.api.nvim_create_augroup('PiNvim', { clear = true })

  -- On VimResume: re-sync messages via get_messages
  vim.api.nvim_create_autocmd('VimResume', {
    group = augroup,
    callback = function()
      if require('pi-nvim.state').connected then
        require('pi-nvim.session').resync()
      end
    end,
  })

  -- On VimLeavePre: graceful shutdown
  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = augroup,
    callback = function()
      require('pi-nvim.session').shutdown()
    end,
  })

  -- Check for pi CLI availability
  local pi_check = vim.fn.executable('pi') == 1
  if not pi_check then
    vim.notify('[pi-nvim] Warning: `pi` CLI not found in $PATH. Install with: npm install -g @mariozechner/pi-coding-agent', vim.log.levels.WARN)
  end

  return M
end

-- Public API
M.toggle_split = function()
  require('pi-nvim.ui.layout').toggle_split()
end

M.toggle_fullscreen = function()
  require('pi-nvim.ui.layout').toggle_fullscreen()
end

M.send_selection = function()
  require('pi-nvim.ui.overlay').send_selection()
end

M.new_session = function()
  require('pi-nvim.session').new()
end

M.resume = function()
  require('pi-nvim.session').resume()
end

M.restart = function()
  require('pi-nvim.session').restart()
end

M.abort = function()
  require('pi-nvim.rpc').abort()
end

M.status = function()
  return require('pi-nvim.ui.status').get_status_line()
end

M.diff_clear = function()
  require('pi-nvim.ui.diff').clear_all()
end

return M