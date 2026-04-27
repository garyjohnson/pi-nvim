--- Default configuration for pi-nvim.
local M = {}

M.defaults = {
  -- Log level: vim.log.levels.TRACE, DEBUG, INFO, WARN, ERROR
  log_level = vim.log.levels.INFO,

  -- Socket path template. {pid} is replaced with neovim's PID.
  sock_path_template = "/tmp/pi-nvim-{pid}.sock",

  -- Whether to automatically start the server on plugin load
  auto_start = false,

  -- Whether to automatically start the server when opening a pi split
  start_on_split = true,

  -- Auto-open files in nvim when pi uses the edit or write tools
  auto_open = true,

  -- Show a git diff in diffthis mode when auto_open is triggered
  show_diff = true,

  -- Direction for the diff split: "vertical" or "horizontal"
  diff_split = "vertical",
}

M.options = {}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

function M.get()
  return M.options
end

return M