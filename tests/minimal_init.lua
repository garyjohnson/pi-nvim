-- Minimal Neovim config for running tests headlessly
-- Usage:
--   nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

-- Discover where this file lives so we can set rtp correctly
local this_file = debug.getinfo(1, 'S').source:sub(2)
local root_dir = vim.fn.fnamemodify(this_file, ':h:h')

-- Path to plenary.nvim (auto-cloned if missing)
local deps_dir = vim.fn.stdpath('data') .. '/site/pack/deps/start'
vim.fn.mkdir(deps_dir, 'p')
local plenary_dir = deps_dir .. '/plenary.nvim'

local function bootstrap_plenary()
  if vim.fn.isdirectory(plenary_dir) == 0 then
    local repo = 'https://github.com/nvim-lua/plenary.nvim'
    vim.fn.system({ 'git', 'clone', '--depth=1', repo, plenary_dir })
    if vim.v.shell_error ~= 0 then
      error('failed to clone plenary.nvim')
    end
  end
end

-- Only clone deps in CI / headless; skip if plenary is already on rtp
local plenary_on_rtp = vim.tbl_contains(vim.api.nvim_list_runtime_paths(), plenary_dir)
if not plenary_on_rtp then
  bootstrap_plenary()
  vim.opt.rtp:prepend(plenary_dir)
end

-- Add the plugin itself to the runtime path
vim.opt.rtp:prepend(root_dir)

-- Ensure Lua modules resolve
package.path = package.path .. ';' .. root_dir .. '/lua/?.lua'
package.path = package.path .. ';' .. root_dir .. '/lua/?/init.lua'

-- Load the plugin
require('pi-nvim').setup()
