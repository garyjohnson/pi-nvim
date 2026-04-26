pi-nvim - A neovim plugin for the pi coding agent
=============================================

 SUMMARY
---------

pi-nvim integrates the [pi coding agent](https://pi.dev) as a first-class
neovim citizen. The human editor and the LLM have equal focus - toggle
between neovim-only, split view, and pi-fullscreen layouts.

 REQUIREMENTS
------------

- Neovim 0.10+
- Node.js and npm
- pi CLI: `npm install -g @mariozechner/pi-coding-agent`

 INSTALLATION
------------

### lazy.nvim

```lua
{ 'yourname/nvim-pi-thing', config = function() require('pi-nvim').setup() end }
```

### vim-plug

```vim
Plug 'yourname/nvim-pi-thing'
```

Then run `:PlugInstall`

 QUICK START
-----------

After installation, the plugin激活ates automatically. Configure it:

```lua
require('pi-nvim').setup({
  -- Default keybindings:
  -- <leader>pt - Toggle pi split view
  -- <leader>pf - Toggle pi fullscreen  
  -- <leader>ps - Send selection to pi
  -- <leader>pn - New session
  -- <leader>pr - Resume/switch session
  -- <leader>pa - Abort current operation
  -- <leader>pi - Jump to pi input buffer
  -- <leader>po - Jump to pi chat buffer
  -- <leader>pd - Clear diff decorations
})
```

Get started:

1. Run `:PiResume` or just start typing in the pi input buffer
2. First interaction starts the pi RPC process
3. Ask pi questions: "What files are in this project?"
4. Send code with `<leader>ps` (visual mode) or from normal mode

 COMMANDS
--------

| Command | Description |
|---------|-------------|
| `:PiToggle` | Toggle pi split view on/off |
| `:PiFullscreen` | Toggle pi fullscreen |
| `:PiSendSelection` | Send selection to pi |
| `:PiNewSession` | Start new pi session |
| `:PiResume` | Resume or switch session |
| `:PiRestart` | Restart pi process |
| `:PiAbort` | Abort current operation |
| `:PiJumpInput` | Jump to pi input buffer |
| `:PiJumpOutput` | Jump to pi chat buffer |
| `:PiDiffClear` | Clear diff decorations |
| `:PiStatus` | Show pi status |
| `:PiFollowUp` | Send follow-up message |

 CONFIGURATION
--------------

```lua
require('pi-nvim').setup({
  -- Layout
  layout = 'adaptive',      -- 'vertical', 'horizontal', 'adaptive'
  split_width = 50,         -- columns for vertical split
  split_height = 20,        -- rows for horizontal split

  -- Session
  session_resume = 'ask',   -- 'new', 'continue', 'ask'

  -- Input
  input_autoinsert = true,  -- auto-enter insert mode in input buffer
  send_key = '<CR>',        -- key to send prompt

  -- Auto-save before prompting
  auto_save = 'ask',        -- 'always', 'never', 'ask'

  -- Diff
  diff_auto_open = true,    -- auto-open changed files
  diff_highlight = true,    -- show inline diffs

  -- Keybindings (customize if needed)
  keys = {
    toggle = '<leader>pt',
    fullscreen = '<leader>pf',
    send_selection = '<leader>ps',
    new_session = '<leader>pn',
    resume = '<leader>pr',
    abort = '<leader>pa',
    jump_input = '<leader>pi',
    jump_output = '<leader>po',
    clear_diffs = '<leader>pd',
  },
})
```

 LUALINE INTEGRATION
-------------------

```lua
require('lualine').setup({
  sections = {
    lualine_c = {
      function() return require('pi-nvim.ui.status').get_status_line() end,
    },
  },
})
```

 FILES
-----

The plugin manages file changes from pi:

- When pi edits a file that's already open: reloads and shows diff
- When pi edits a new file: auto-opens in buffer (configurable)
- Diff decorations show added/changed/deleted lines inline
- Use `:PiDiffClear` or `<leader>pd` to clear decorations

 TROUBLESHOOTING
--------------

### pi CLI not found

Install it: `npm install -g @mariozechner/pi-coding-agent`

### pi process won't start

Check your API key is set:
```bash
export ANTHROPIC_API_KEY=sk-ant-...
```

Or use `/login` in pi directly to authenticate.

### Keybindings don't work

Make sure `<leader>` is set. The default leader is space:
```vim
let mapleader = " "
```

### Want to start fresh

Run `:PiNewSession` or delete session files in `~/.pi/agent/sessions/`

 ABOUT
-----

pi-nvim integrates pi (https://pi.dev), a minimal terminal coding harness
that adapts to your workflows. The plugin builds a neovim-native UI on top
of pi's RPC mode.

License: MIT