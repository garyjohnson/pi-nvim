-- pi-nvim UI status module
-- Status line indicators and global notifications

local state = require('pi-nvim.state')
local config = require('pi-nvim.config')

local M = {}

-- Status string for pi window
function M.get_pi_status()
  local model_name = state.model and state.model.name or 'unknown'

  if state.streaming then
    return '⏳ streaming | ' .. model_name
  elseif state.thinking then
    return '💭 thinking | ' .. model_name
  elseif state.is_compacting then
    return '🔄 compacting | ' .. model_name
  else
    return '● idle | ' .. model_name
  end
end

-- Setup pi window statusline
function M.setup_pi_statusline(winid)
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    return
  end

  -- Set custom statusline for pi window
  vim.api.nvim_win_set_option(winid, 'statusline', '%!v:lua.require("pi-nvim.ui.status").get_pi_status()')
end

-- Get global status for use in user's statusline
function M.get_status_line()
  if not state.connected then
    return ''
  end

  if state.streaming then
    return '⏳ pi: working' .. (state.model and (' (' .. state.model.name .. ')') or '')
  elseif state.thinking then
    return '💭 pi: thinking' .. (state.model and (' (' .. state.model.name .. ')') or '')
  else
    return '● pi: idle' .. (state.model and (' (' .. state.model.name .. ')') or '')
  end
end

-- Get model display string
function M.get_model_display()
  return state.model and state.model.name or ''
end

-- Get tokens/cost display string
function M.get_stats_display()
  return state.tokens_in .. ' in / ' .. state.tokens_out .. ' out | $' .. string.format('%.2f', state.total_cost)
end

-- Update from stats
function M.update_stats(stats)
  if stats then
    if stats.tokens then
      state.tokens_in = stats.tokens.input or 0
      state.tokens_out = stats.tokens.output or 0
    end
    if stats.cost then
      state.total_cost = stats.cost or 0
    end
  end
end

-- Update status (called by event handlers)
function M.update()
  -- Force statusline refresh
  vim.cmd('redrawstatus')
end

-- Lualine component for integration
function M.lualine_component()
  return M.get_status_line()
end

return M