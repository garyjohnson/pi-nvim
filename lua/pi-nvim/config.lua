-- pi-nvim configuration module
-- Default configuration and user overrides

local M = {}

local defaults = {
  -- Layout
  layout = 'adaptive',           -- 'vertical' | 'horizontal' | 'adaptive'
  split_width = 50,              -- columns for vertical split
  split_height = 20,             -- rows for horizontal split

  -- Session
  session_resume = 'ask',        -- 'new' | 'continue' | 'ask'

  -- Input
  input_autoinsert = true,       -- auto-enter insert mode in input buffer
  send_key = '<CR>',             -- key to send prompt from input buffer
  auto_save = 'ask',             -- 'always' | 'never' | 'ask'

  -- Diff
  diff_auto_open = true,         -- auto-open changed files in buffers
  diff_highlight = true,          -- show inline diff decorations

  -- Keybindings
  keys = {
    toggle = '<leader>pt',       -- toggle split on/off
    fullscreen = '<leader>pf',   -- toggle pi fullscreen
    send_selection = '<leader>ps', -- send selection to pi
    new_session = '<leader>pn',  -- new pi session
    resume = '<leader>pr',       -- resume/switch session
    abort = '<leader>pa',        -- abort current operation
    jump_input = '<leader>pi',   -- focus pi input buffer
    jump_output = '<leader>po',   -- focus pi chat buffer
    clear_diffs = '<leader>pd',  -- clear diff decorations
  },
}

-- Deep merge two tables
local function merge(overrides, base)
  local result = {}
  for k, v in pairs(base or {}) do
    if type(v) == 'table' and type(overrides[k]) == 'table' then
      result[k] = merge(overrides[k], v)
    else
      result[k] = overrides[k] ~= nil and overrides[k] or v
    end
  end
  for k, v in pairs(overrides or {}) do
    if result[k] == nil then
      result[k] = v
    end
  end
  return result
end

function M.setup(user_config)
  M.config = merge(user_config or {}, defaults)
  return M.config
end

function M.get()
  if not M.config then
    M.config = defaults
  end
  return M.config
end

return M