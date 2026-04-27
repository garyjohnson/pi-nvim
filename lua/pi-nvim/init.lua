--- pi-nvim: Neovim integration for the pi coding agent.
--- Exposes editor state via a unix domain socket so that pi (running in
--- a terminal split) can query buffers, selections, and viewport context
--- through custom tools registered by the companion extension.
local M = {}

local config = require("pi-nvim.config")
local server = require("pi-nvim.server")
local handlers = require("pi-nvim.handlers")

-- Track the buffer number of the pi terminal we launched
local pi_bufnr = nil

--- Start the unix socket server and register JSON-RPC handlers.
---@return string|nil sock_path The socket path, or nil on failure
function M.start_server()
  if server.is_running() then
    return server.get_sock_path()
  end

  local opts = config.get()
  handlers.register_all()

  local sock_path = server.start({
    log_level = opts.log_level,
  })

  if sock_path then
    -- Clean up on exit
    vim.api.nvim_create_autocmd("VimLeavePre", {
      group = "pi-nvim",
      callback = function()
        M.stop_server()
      end,
    })
  end

  return sock_path
end

--- Stop the unix socket server and clean up.
function M.stop_server()
  server.stop()
end

--- Open pi in a vertical terminal split, with the extension loaded and
--- the neovim socket address passed via PI_NVIM_SOCK.
function M.open_split()
  local opts = config.get()

  -- Start the server if needed
  local sock_path
  if opts.start_on_split then
    sock_path = M.start_server()
  end

  -- If we already launched a pi terminal and it's still valid, focus it
  if pi_bufnr and vim.api.nvim_buf_is_valid(pi_bufnr) and vim.bo[pi_bufnr].buftype == "terminal" then
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == pi_bufnr then
        vim.api.nvim_set_current_win(win)
        return
      end
    end

    -- Buffer exists but hidden — open it in a right-hand split
    vim.cmd("rightbelow vsplit")
    vim.api.nvim_win_set_buf(0, pi_bufnr)
    return
  end

  -- Determine the extension path relative to this plugin's root
  local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")
  local ext_path = plugin_root .. "/extension/src/index.ts"

  -- Build the pi command
  local pi_cmd = string.format("pi -e %s", vim.fn.shellescape(ext_path))

  -- Build the termopen options
  local term_opts = { cwd = vim.fn.getcwd() }
  if sock_path then
    -- Merge current environment with PI_NVIM_SOCK
    -- termopen env replaces the entire environment, so we must inherit
    local merged_env = vim.fn.environ()
    merged_env["PI_NVIM_SOCK"] = sock_path
    term_opts.env = merged_env
  end

  -- Create a split and start pi in a terminal
  vim.cmd("rightbelow vsplit | enew")
  vim.fn.termopen(pi_cmd, term_opts)
  pi_bufnr = vim.api.nvim_get_current_buf()

  -- Auto-enter insert mode in the pi terminal whenever it gains focus
  vim.api.nvim_create_autocmd("BufWinEnter", {
    buffer = pi_bufnr,
    callback = function()
      vim.cmd("startinsert")
    end,
  })

  -- Press Esc to exit terminal mode for window navigation
  vim.keymap.set("t", "<Esc>", "<C-\\><C-n>", { buffer = pi_bufnr, silent = true })

  -- Ctrl-w exits terminal mode then sends the window command prefix
  vim.keymap.set("t", "<C-w>", "<C-\\><C-n><C-w>", { buffer = pi_bufnr, silent = true })

  -- Start insert mode immediately on first open
  vim.cmd("startinsert")
end

--- Setup the plugin with user configuration.
---@param opts? table User options merged with defaults
function M.setup(opts)
  config.setup(opts)

  -- Create an augroup for cleanup
  vim.api.nvim_create_augroup("pi-nvim", { clear = true })

  -- Start the server automatically if configured
  if config.get().auto_start then
    M.start_server()
  end
end

return M