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

  -- Whether to open files in a split window instead of the current window
  open_in_split = false,

  -- Split direction: "vertical" or "horizontal"
  split_direction = "vertical",

  -- Whether to show a git diff when opening a file that is tracked by git
  show_git_diff = false,
}

M.options = {}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

function M.get()
  return M.options
end

return M