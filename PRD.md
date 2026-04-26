# nvim-pi-thing — Product Requirements & Design Specification

A neovim plugin that integrates the pi coding agent as a first-class neovim citizen. Pi runs as an RPC subprocess; neovim provides a native UI. The human editor and the LLM have equal focus — toggle between neovim-only, split view, and pi-fullscreen layouts.

## 1. Architecture

### Integration: RPC mode

`pi --mode rpc` spawned as a child process. JSONL over stdio. Language-agnostic, process-isolated, simple protocol.

- Process isolation: pi crashing doesn't kill neovim and vice versa
- Pi sessions persist on disk; crash recovery via `:PiResume`
- Upgrade decoupled: pi updates independently

### UI: Neovim-native

No terminal buffers. Chat buffer renders markdown. Input buffer uses neovim editing. Diff decorations use extmarks. Floating windows for the selection overlay.

### Async: `vim.fn.jobstart()`

Spawns pi, receives stdout lines via `on_stdout` callback. Each line parsed as JSON via `vim.json.decode()`. Incomplete JSON lines buffered across callbacks.

## 2. Plugin Structure

```
nvim-pi-thing/
├── lua/
│   └── pi-nvim/
│       ├── init.lua           — setup(), public API
│       ├── rpc.lua            — spawn pi, send commands, parse events
│       ├── ui/
│       │   ├── layout.lua     — window management, split/fullscreen toggle
│       │   ├── chat.lua       — chat buffer, message rendering, markdown
│       │   ├── input.lua      — input buffer, send/steer/follow-up
│       │   ├── overlay.lua    — floating window for send-selection
│       │   └── diff.lua       — inline diff decorations on changed buffers
│       ├── session.lua        — lifecycle: start, stop, resume, new
│       ├── state.lua          — shared state: streaming, messages, model
│       └── config.lua         — defaults + user overrides
├── plugin/
│   └── pi-nvim.lua            — autocmds, commands, keybindings
├── doc/
│   └── pi-nvim.txt           — :help docs
└── README.md
```

## 3. Configuration

```lua
require('pi-nvim').setup({
  layout = 'adaptive',           -- 'vertical' | 'horizontal' | 'adaptive'
  split_width = 50,             -- columns for vertical split
  split_height = 20,            -- rows for horizontal split
  session_resume = 'ask',       -- 'new' | 'continue' | 'ask'
  input_autoinsert = true,      -- auto-enter insert mode in input buffer
  send_key = '<CR>',            -- key to send prompt from input buffer
  auto_save = 'ask',            -- 'always' | 'never' | 'ask'
  diff_auto_open = true,         -- auto-open changed files in buffers
  diff_highlight = true,          -- show inline diff decorations
  keys = {
    toggle = '<leader>pt',       -- toggle split on/off
    fullscreen = '<leader>pf',   -- toggle pi fullscreen
    send_selection = '<leader>ps', -- send selection to pi
    new_session = '<leader>pn',  -- new pi session
    resume = '<leader>pr',       -- resume/switch session
    abort = '<leader>pa',        -- abort current operation
    jump_input = '<leader>pi',   -- focus pi input buffer
    jump_output = '<leader>po',   -- focus pi chat buffer
    clear_diffs = '<leader>pd',    -- clear diff decorations
  },
})
```

## 4. Layout System

Three states, two toggles:

- **`<leader>pt`** — Toggle split on/off. When on: vertical or horizontal split (adaptive to screen size). When off: neovim fullscreen, pi hidden.
- **`<leader>pf`** — Toggle pi fullscreen. Expands pi's panel to fill the entire editor. Toggle back to split view.

Pi panel contains two buffers stacked vertically:

- **Chat buffer** (top, read-only) — conversation history, rendered markdown
- **Input buffer** (bottom, editable) — prompt composition, insert mode by default

Adaptive logic: vertical split when `&columns >= &lines * 2`, horizontal otherwise. User can override with `layout` setting.

## 5. Input Buffer

- **`<CR>`** sends the prompt. When pi is streaming, sends as steering message. When idle, sends as normal prompt.
- **`<S-CR>`** inserts a newline. Configurable fallback (`<C-s>`, `<C-CR>`) for terminals where Shift+Enter doesn't work.
- **`<Esc>`** jumps back to previous neovim window.
- **`<C-C>`** clears the input buffer.
- Auto-enters insert mode on focus when `input_autoinsert = true` (default).
- `@` file references, `!command`, `/commands` passed through to pi as-is.
- `:PiFollowUp` for power-user follow-up messages during streaming.

## 6. Send Selection Overlay (`<leader>ps`)

When pi is hidden and user hits `<leader>ps` with a visual selection (or current line in normal mode):

1. Floating window appears, centered, ~60% width × ~40% height
2. Selection pre-filled as fenced code block with file path and line numbers:
   ````markdown
   ```/src/app.ts:42-58
   function processOrder(order) {
     ...
   }
   ```
   ````
3. User types instructions below the selection
4. `<CR>` sends, `<Esc>` cancels
5. If pi is streaming, shows "⏳ pi is working — message will be queued"
6. On send: overlay closes, notification "✓ sent to pi"
7. If pi is already visible in split, `<leader>ps` pre-fills pi's input buffer and focuses it instead of showing overlay.

## 7. Chat Buffer Rendering

- **User messages**: `PiUserMsg` highlight group, `>` prefix
- **Assistant text**: Regex-based markdown rendering (headers, bold, code fences, inline code, links). Code blocks get filetype-detected treesitter highlighting where available.
- **Thinking blocks**: Folded by default, `PiThinking` highlight group, expandable.
- **Tool calls**: Collapsed by default — show `▶ read src/app.ts` or `▶ edit src/app.ts`. Expandable to see args/results. `PiToolCall` highlight group.
- **Tool results**: Folded inside tool call. File reads show path + line count, not full content. Errors highlighted in `PiError`.
- Streaming text appended in real-time via `message_update` deltas.

## 8. File Change Detection & Diff

### Detection

On `tool_execution_end` for `write`/`edit` tools:

1. Parse tool args to extract file path
2. If file is open in a buffer and unmodified: force-reload from disk, then apply diff decorations
3. If file is open and modified (unsaved user edits): don't overwrite, show notification "⚠ pi changed `src/app.ts` but you have unsaved edits. `:PiDiff` to compare."
4. If file is not open and `diff_auto_open = true`: open in buffer list without stealing focus
5. Notification listing all changed files: "pi edited 3 files: app.ts, util.ts, test.ts"
6. `bash` tool changes: ignored for MVP. `:PiDiffScan` command available for manual git-diff check.

### Diff Decorations

- Computed via `vim.diff()` between pre-change buffer content and post-change disk content
- Applied as extmarks with highlight groups: `DiffAdd` (green bg), `DiffChange` (yellow bg), `DiffDelete` (red bg + virtual text showing deleted lines)
- Persist until explicitly cleared with `<leader>pd` or `:PiDiffClear`
- Optional auto-clear on `agent_start` (configurable)

## 9. Session Management

- **Startup**: Pi RPC process launches on first interaction (lazy start). Not on plugin load.
- **Session resume**: Configurable `session_resume` setting:
  - `"new"` — always fresh session
  - `"continue"` — auto-resume most recent
  - `"ask"` (default) — `vim.ui.select()` with "New session" + recent sessions
- **One session per working directory**: Pi organizes sessions by cwd. Spawn `pi --mode rpc` with the project root as cwd.
- **Shutdown**: On `VimLeavePre`, send `abort` RPC command, wait 2s, then `jobstop()`.
- **Crash recovery**: Pi crash enters "disconnected" state. Chat buffer preserved. `:PiRestart` to reconnect. `:PiResume` to continue previous session.

## 10. Auto-Save

Before sending a prompt, check for modified buffers:

- `"ask"` (default): notification asking "Save modified buffers?" yes/no/cancel
- `"always"`: silent `:wa`
- `"never"`: send as-is, pi reads from disk

## 11. Streaming & Steering

- `<CR>` in input buffer: if pi is streaming → send as steering message; if idle → send as normal prompt. User doesn't need to think about it.
- `:PiFollowUp` or `<leader>pF` for follow-up messages (advanced).
- **Steering**: delivered after current tool execution, before next LLM call.
- **Follow-up**: delivered only after agent finishes all work.

## 12. Status & Notifications

### Pi panel status line

```
● claude-sonnet-4 | ctx 32% | $0.14 | 847 in / 203 out
```

### Input buffer border color

- Gray: idle
- Yellow/orange: thinking
- Green: streaming text
- Red: error

### Global status when hidden

`PiStatus()` function returns:
- `""` when no session active
- `"● pi: idle (claude-sonnet-4)"` when idle
- `"⏳ pi: working (claude-sonnet-4)"` when streaming

Provided as a lualine component and usable in `&statusline`.

### Notifications via `vim.notify()`

| Event | Notification |
|---|---|
| pi process starts | "pi session started" |
| pi process exits/crashes | "⚠ pi process exited (code X)" |
| File changed by pi | "pi edited 3 files: app.ts, util.ts, test.ts" |
| Steering message queued | "✓ message queued (pi is working)" |
| Agent completes a turn | "✓ pi finished" (only when hidden) |
| Error in agent response | "✗ pi error: rate limit exceeded" |
| Unsaved buffer conflict | "⚠ pi changed src/app.ts but you have unsaved edits" |

## 13. RPC Command Priority

### MVP (day one)

**Commands:** `prompt`, `abort`, `get_state`, `get_messages`, `steer`, `follow_up`

**Events:** `agent_start/end`, `message_start/update/end`, `turn_start/end`, `tool_execution_start/end`, `queue_update`

### Next iteration

**Commands:** `new_session`, `get_available_models`, `set_model`, `get_session_stats`, `compact`, `set_thinking_level`

**Events:** `auto_retry_start/end`, `compaction_start/end`

**Extension UI:** `extension_ui_request` for `select`/`confirm`/`input` → `vim.ui.select()` / `vim.ui.input()`

### Later

**Commands:** `switch_session`, `fork`, `clone`, `export_html`, `bash`, `cycle_model`, `get_commands`

## 14. Resilience

- **Pi crash**: Disconnected state. Chat buffer preserved. `:PiRestart` to reconnect.
- **Network issues**: Handled by pi internally (auto-retry). Rendered as error states in chat.
- **Neovim suspend**: On `VimResume` autocmd, send `get_messages` RPC to re-sync chat buffer.
- **Buffer conflicts**: Unsaved user edits never overwritten by pi changes.

## 15. Keybinding Summary

| Binding | Mode | Action |
|---------|------|--------|
| `<leader>pt` | Normal | Toggle split on/off |
| `<leader>pf` | Normal | Toggle pi fullscreen |
| `<leader>ps` | Normal/Visual | Send selection to pi |
| `<leader>pn` | Normal | New pi session |
| `<leader>pr` | Normal | Resume/switch session |
| `<leader>pa` | Normal | Abort current operation |
| `<leader>pi` | Normal | Jump to pi input buffer |
| `<leader>po` | Normal | Jump to pi chat buffer |
| `<leader>pd` | Normal | Clear diff decorations |
| `<CR>` | Insert (input) | Send prompt (steer if streaming) |
| `<S-CR>` | Insert (input) | New line |
| `<Esc>` | Insert (input) | Jump back to code |
| `<C-C>` | Insert (input) | Clear input |

## 16. Dependencies

- **Required**: Neovim 0.10+, pi CLI (`npm install -g @mariozechner/pi-coding-agent`)
- **Optional**: nvim-treesitter (markdown rendering), telescope/fzf-lua (session/model pickers), nvim-notify (pretty notifications)
- **Zero hard dependencies** beyond neovim and pi.
- On startup, check for `pi` on `$PATH` and verify minimum version. Fail gracefully with clear message if missing.