-- pi-nvim UI diff module
-- Detects file changes and renders inline diffs

local state = require('pi-nvim.state')
local config = require('pi-nvim.config')
local session = require('pi-nvim.session')

local M = {}

-- Track what files pi has changed
local changed_files = {}

-- Process a tool execution event
function M.track_changes(event)
  local tool_name = event.tool_name

  if tool_name == 'write' or tool_name == 'edit' then
    local args = event.args or {}
    local file_path = args.file or args.path

    if file_path then
      changed_files[file_path] = event
    end
  end

  if event.result then
    -- tool_execution_end - process the result
    M.on_tool_complete(event)
  end
end

-- Handle tool completion
function M.on_tool_complete(event)
  local tool_name = event.tool_name

  if tool_name == 'write' or tool_name == 'edit' then
    local args = event.args or {}
    local file_path = args.file or args.path
    local result = event.result

    if not file_path then
      return
    end

    -- Find buffer with this file (if open)
    local bufnr = vim.fn.bufnr(file_path)

    if bufnr > 0 and vim.api.nvim_buf_is_valid(bufnr) then
      -- Buffer is open
      local is_modified = vim.api.nvim_buf_get_option(bufnr, 'modified')

      if is_modified then
        -- Unsaved user changes - don't overwrite, notify
        vim.notify('[pi-nvim] ⚠ pi changed ' .. file_path .. ' but you have unsaved edits. Use :PiDiff to compare.', vim.log.levels.WARN)
      else
        -- Reload and show diff
        M.reload_and_diff(bufnr, file_path)
      end
    else
      -- Buffer not open - should we open it?
      local cfg = config.get()
      if cfg.diff_auto_open then
        -- Open file in buffer (don't steal focus)
        vim.cmd('edit ' .. file_path)

        -- Get the new buffer number
        local new_bufnr = vim.fn.bufnr(file_path)
        if new_bufnr > 0 then
          M.apply_diff_decorations(new_bufnr)
        end
      end
    end

    -- Track for notification
    table.insert(changed_files, file_path)
  end
end

-- Reload buffer and apply diff decorations
function M.reload_and_diff(bufnr, file_path)
  -- Force reload from disk
  vim.cmd('checktime ' .. bufnr)
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd('edit!')
  end)

  -- Apply diff decorations
  M.apply_diff_decorations(bufnr)
end

-- Apply diff decorations to a buffer
function M.apply_diff_decorations(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Get current buffer content
  local current_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local current_time = vim.fn.getftime(vim.api.nvim_buf_get_name(bufnr))

  -- Try to read from disk
  local disk_lines = {}
  local handle = io.open(vim.api.nvim_buf_get_name(bufnr), 'r')
  if handle then
    for line in handle:lines() do
      table.insert(disk_lines, line)
    end
    handle:close()
  else
    return
  end

  -- Compute diff
  local old = table.concat(current_lines, '\n')
  local new = table.concat(disk_lines, '\n')

  -- Use vim.diff to compute hunk info
  local diff_result = vim.diff(old, new, {
    preserve_white_space = true,
    ignore_white_space = true,
  })

  if not diff_result or diff_result == '' then
    return
  end

  -- Parse diff and apply decorations
  local ns = vim.api.nvim_create_namespace('pi-diff')

  -- Clear existing diff decorations
  M.clear(bufnr)

  local cleanup_fn = function()
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    end
  end

  state.track_diff_buffer(bufnr, cleanup_fn)

  -- Parse diff hunks and apply highlights
  for line_num, line in ipairs(disk_lines) do
    local line_content = line

    -- Simple heuristic: if line is in diff but not in old, it's an addition
    -- For a proper implementation, parse the full diff
    -- This is simplified for MVP
  end

  -- Show notification
  local file_name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ':t')
  local count = #disk_lines - #current_lines
  local change_str = count > 0 and ('+' .. count) or tostring(count)

  vim.notify('[pi-nvim] pi edited ' .. file_name .. ': ' .. change_str .. ' lines', vim.log.levels.INFO)
end

-- Clear diff decorations for a buffer
function M.clear(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local ns = vim.api.nvim_create_namespace('pi-diff')
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  state.clear_diff_buffer(bufnr)
end

-- Clear all diff decorations
function M.clear_all()
  state.clear_all_diffs()
end

-- Show diff between buffer and disk
function M.show_diff(bufnr)
  if not bufnr then
    bufnr = vim.fn.bufnr('%')
  end

  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Write the buffer to temp, then run difftool, or use vim.diff
  local buf_name = vim.api.nvim_buf_get_name(bufnr)
  local cmd = 'diff -u ' .. buf_name .. ' ' .. buf_name .. ' | head -100'
  vim.cmd('belowright new')
  vim.api.nvim_put(vim.split(vim.fn.system(cmd), '\n'), '', true)
end

return M