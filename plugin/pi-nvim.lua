-- pi-nvim plugin entry point
-- This file loads when neovim starts with this plugin in rtp

local pi = require('pi-nvim')

vim.api.nvim_create_user_command('PiSplit', pi.open_split, {
  desc = 'Open pi coding agent in a vertical terminal split',
})

-- Setup the plugin with default configuration (reserved for future use)
pi.setup()
