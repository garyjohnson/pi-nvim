local M = {}

-- Track the buffer number of the pi terminal we launched
local pi_bufnr = nil

function M.open_split()
  -- If we've already launched a pi terminal and it's still a valid terminal buffer, focus it
  if pi_bufnr and vim.api.nvim_buf_is_valid(pi_bufnr) and vim.bo[pi_bufnr].buftype == 'terminal' then
    -- Is it visible in a window already?
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == pi_bufnr then
        vim.api.nvim_set_current_win(win)
        return
      end
    end

    -- Buffer exists but hidden — open it in a right-hand split
    vim.cmd('rightbelow vsplit')
    vim.api.nvim_win_set_buf(0, pi_bufnr)
    return
  end

  -- Create a new right-hand split with an empty buffer, then start pi in a terminal
  vim.cmd('rightbelow vsplit | enew')
  local cwd = vim.fn.getcwd()
  vim.fn.termopen('pi', { cwd = cwd })
  pi_bufnr = vim.api.nvim_get_current_buf()
end

function M.setup()
  -- Reserved for future configuration (split direction, command name, etc.)
end

return M
