local pi = require('pi-nvim')

describe('PiSplit terminal-mode keymaps', function()
  before_each(function()
    -- Close all windows except one and delete all buffers for a clean slate
    vim.cmd('silent! %bwipeout!')
    vim.cmd('silent! only')
  end)

  it('should set buffer-local <Esc> mapping in terminal mode', function()
    pi.open_split()
    local bufnr = vim.api.nvim_get_current_buf()

    local maps = vim.api.nvim_buf_get_keymap(bufnr, 't')
    local esc_map = vim.tbl_filter(function(m)
      return m.lhs == '<Esc>'
    end, maps)

    assert.equals(1, #esc_map, 'expected exactly one <Esc> mapping in terminal mode')
    -- The mapping should exit terminal mode: <C-\><C-N>
    assert.equals('<C-\\><C-N>', esc_map[1].rhs)
    assert.equals(bufnr, esc_map[1].buffer, 'mapping should be buffer-local')
  end)

  it('should set buffer-local <C-w> mapping in terminal mode', function()
    pi.open_split()
    local bufnr = vim.api.nvim_get_current_buf()

    local maps = vim.api.nvim_buf_get_keymap(bufnr, 't')
    local cw_map = vim.tbl_filter(function(m)
      return m.lhs == '<C-W>'
    end, maps)

    assert.equals(1, #cw_map, 'expected exactly one <C-w> mapping in terminal mode')
    -- The mapping should exit terminal mode then send <C-w>: <C-\><C-N><C-W>
    assert.equals('<C-\\><C-N><C-W>', cw_map[1].rhs)
    assert.equals(bufnr, cw_map[1].buffer, 'mapping should be buffer-local')
  end)

  it('should not set terminal-mode mappings on other buffers', function()
    -- Create a regular buffer that is NOT the pi terminal
    local other_buf = vim.api.nvim_create_buf(true, false)

    local maps = vim.api.nvim_buf_get_keymap(other_buf, 't')
    local esc_map = vim.tbl_filter(function(m)
      return m.lhs == '<Esc>'
    end, maps)
    local cw_map = vim.tbl_filter(function(m)
      return m.lhs == '<C-W>'
    end, maps)

    assert.equals(0, #esc_map, '<Esc> should not be mapped on non-pi buffers')
    assert.equals(0, #cw_map, '<C-w> should not be mapped on non-pi buffers')
  end)

  it('should set BufWinEnter autocmd for auto-insert on the pi terminal buffer', function()
    pi.open_split()
    local bufnr = vim.api.nvim_get_current_buf()

    local autocmds = vim.api.nvim_get_autocmds({
      event = 'BufWinEnter',
      buffer = bufnr,
    })

    -- Filter to autocmds created by our plugin (callback-based, not command-based)
    local pi_autocmds = vim.tbl_filter(function(a)
      return a.command == '' -- callback autocmds have empty command field
    end, autocmds)

    assert.is.truthy(#pi_autocmds > 0, 'expected at least one BufWinEnter autocmd on pi buffer')
  end)
end)