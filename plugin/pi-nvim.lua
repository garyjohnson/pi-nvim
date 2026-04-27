-- pi-nvim plugin entry point
-- This file loads when neovim starts with this plugin in rtp

local pi = require("pi-nvim")

vim.api.nvim_create_user_command("PiSplit", pi.open_split, {
  desc = "Open pi coding agent in a vertical terminal split",
})

vim.api.nvim_create_user_command("PiStartServer", pi.start_server, {
  desc = "Start the pi-nvim socket server without opening a split",
})

vim.api.nvim_create_user_command("PiStopServer", pi.stop_server, {
  desc = "Stop the pi-nvim socket server",
})

-- Setup the plugin with default configuration
pi.setup()