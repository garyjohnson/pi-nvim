local pi = require('pi-nvim')

describe('PiSplit', function()
  before_each(function()
    -- Close all windows except one and delete all buffers for a clean slate
    vim.cmd('silent! %bwipeout!')
    vim.cmd('silent! only')
  end)

  it('should create a terminal buffer and a new window', function()
    local initial_win_count = #vim.api.nvim_tabpage_list_wins(0)

    pi.open_split()

    -- We should now have one more window
    assert.equals(initial_win_count + 1, #vim.api.nvim_tabpage_list_wins(0))

    -- The current buffer should be a terminal
    local bufnr = vim.api.nvim_get_current_buf()
    assert.equals('terminal', vim.bo[bufnr].buftype)
  end)

  it('should jump focus to an existing pi terminal instead of spawning a second buffer', function()
    pi.open_split()
    local first_buf = vim.api.nvim_get_current_buf()

    -- Jump back to the original (only) window so we can see if focus moves
    vim.cmd('wincmd h')

    local win_count_before = #vim.api.nvim_tabpage_list_wins(0)

    pi.open_split()

    -- Window count should NOT increase; focus should move to existing
    assert.equals(win_count_before, #vim.api.nvim_tabpage_list_wins(0))
    assert.equals(first_buf, vim.api.nvim_get_current_buf())
  end)

  it('should reopen a hidden pi terminal buffer in a new split', function()
    pi.open_split()
    local buf = vim.api.nvim_get_current_buf()

    -- Close the window (hide the buffer)
    vim.cmd('close')

    local win_count_before = #vim.api.nvim_tabpage_list_wins(0)

    pi.open_split()

    -- Should create a new window for the existing buffer
    assert.equals(win_count_before + 1, #vim.api.nvim_tabpage_list_wins(0))
    assert.equals(buf, vim.api.nvim_get_current_buf())
  end)
end)
