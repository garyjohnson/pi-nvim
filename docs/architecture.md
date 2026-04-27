# pi-nvim Architecture

A neovim plugin that exposes editor state to pi via a unix domain socket, enabling the LLM to read buffers, selections, and viewport context — and to drive neovim actions like opening files.

## Overview

pi-nvim has two components co-located in one repository:

1. **Neovim plugin** (Lua) — creates a unix socket server, gathers editor state, responds to JSON-RPC requests.
2. **Pi extension** (TypeScript) — connects to the socket, registers custom tools that the LLM can call, translates tool calls into JSON-RPC requests.

Communication is bidirectional over a unix domain socket using JSON-RPC 2.0. Neovim is the server; the extension is the client.

```
┌──────────────┐         UNIX socket          ┌──────────────────────┐
│   Neovim     │◄──────────────────────────────►│   Pi Extension       │
│              │   /tmp/pi-nvim-{pid}.sock      │   (in pi process)   │
│  server.lua  │   JSON-RPC 2.0 over \n-delimited│  socket.ts          │
│  handlers.lua│   UTF-8 messages               │  tools.ts            │
│              │                                 │  protocol.ts         │
└──────────────┘                                 └──────────────────────┘
```

## Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Communication channel | Unix domain socket | Bidirectional, no per-call process spawn, filesystem permissions |
| Server side | Neovim | Stable parent process; socket survives pi restarts; no port conflicts |
| Discovery | `PI_NVIM_SOCK` env var | Simplest; neovim controls pi's environment via `termopen` |
| Protocol | JSON-RPC 2.0 | Formal spec, built-in error handling, supports notifications for future use |
| Extension loading | `-e` flag | Extension only loads inside neovim; no leftover auto-discovery in standalone pi |
| Socket type | Separate from `serverstart()` | No collision with neovim's native RPC; we control the full protocol |
| State model | On-demand only | LLM calls tools when it needs context; no proactive push in v1 |
| Handshake | `initialize` with protocol version + PID | Future-proof; verifies correct neovim instance |
| Disconnection | 3 retries × 200ms; then mark disconnected | Handles slow startup and transient drops without over-engineering |
| Logging | Neovim: file in `stdpath("log")`; Extension: `console.*` (pi captures) | Each side uses its platform's natural logging |
| Distribution | Both in pi-nvim repo | Single install, single version, co-versioned protocol |
| Test runner | Neovim: plenary.nvim; Extension: bun test | Plenary for Lua server, bun for TypeScript with mock socket server |

## Connection Lifecycle

1. User runs `:PiSplit`
2. Neovim creates a unix socket server on `/tmp/pi-nvim-{getpid()}.sock`
3. Neovim launches pi via `termopen('pi -e <ext_path>', { env = { PI_NVIM_SOCK = sock_path } })`
4. Pi starts, extension loads, reads `process.env.PI_NVIM_SOCK`
5. If present: extension connects with up to 3 retries (200ms apart)
6. Extension sends `initialize` handshake; neovim responds with `{protocolVersion, pid}`
7. Extension registers 4 tools
8. LLM calls tools → extension sends JSON-RPC requests → neovim responds
9. On pi exit or `session_shutdown`: extension closes connection
10. On `VimLeavePre`: neovim closes server, removes socket file

If `PI_NVIM_SOCK` is absent, the extension does nothing. Pi works normally without neovim integration.

If all retry attempts fail, the extension logs an error and tools return `"Neovim is not connected"` errors.

## Protocol Contract

All messages are JSON-RPC 2.0, newline-delimited (`\n`), UTF-8 encoded.

### `initialize`

Confirm connection and negotiate protocol version.

**Request:**
```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
```

**Response:**
```json
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1,"pid":12345}}
```

### `state`

Broad context: all buffers, windows, cursor positions, selection summary. No buffer content.

**Request:**
```json
{"jsonrpc":"2.0","id":2,"method":"state","params":{}}
```

**Response:**
```json
{
  "mode": "n",
  "currentWin": 1001,
  "lastBuffer": 5,
  "buffers": [
    {
      "bufnr": 1,
      "name": "/path/to/file.lua",
      "listed": true,
      "modified": false,
      "lineCount": 142,
      "filetype": "lua",
      "windows": [1001, 1003]
    }
  ],
  "windows": [
    {
      "winid": 1001,
      "bufnr": 1,
      "cursor": [45, 12],
      "topline": 30,
      "botline": 60
    }
  ],
  "selection": null
}
```

`selection` is `null` when no visual selection is active, or:
```json
{
  "mode": "V",
  "bufnr": 1,
  "name": "/path/to/file.lua",
  "start": [42, 0],
  "end": [58, 0]
}
```

Selection provides position only (no text). The LLM calls `selection` separately for text content.

### `bufContent`

Targeted content retrieval. Full buffer or line range.

**Request:**
```json
{"jsonrpc":"2.0","id":3,"method":"bufContent","params":{"bufnr":1,"start":10,"end":20}}
```

- `bufnr` (required): buffer handle from `state` response
- `start` (optional): 1-indexed start line, inclusive
- `end` (optional): 1-indexed end line, inclusive

Omit `start` and `end` for the full buffer.

**Response:**
```json
{
  "bufnr": 1,
  "name": "/path/to/file.lua",
  "start": 10,
  "end": 20,
  "lines": ["line 10 content", "line 11 content", "..."],
  "totalLines": 142
}
```

### `selection`

Current visual selection text. Returns null fields when in normal mode.

**Request:**
```json
{"jsonrpc":"2.0","id":4,"method":"selection","params":{}}
```

**Response (visual selection active):**
```json
{
  "mode": "V",
  "bufnr": 1,
  "name": "/path/to/file.lua",
  "start": [42, 0],
  "end": [58, 0],
  "text": "function processOrder(order)\n  ...\nend"
}
```

**Response (no selection):**
```json
{
  "mode": "n",
  "bufnr": null,
  "name": null,
  "start": null,
  "end": null,
  "text": null
}
```

### `openFile`

Open a file in neovim, optionally positioning the cursor.

**Request:**
```json
{"jsonrpc":"2.0","id":5,"method":"openFile","params":{"path":"/path/to/file.lua","line":42,"col":0}}
```

- `path` (required): file path to open
- `line` (optional): line number to position cursor
- `col` (optional): column number to position cursor

**Response:**
```json
{"bufnr": 1, "name": "/path/to/file.lua"}
```

### Error Responses

JSON-RPC 2.0 standard error codes:

| Code | Meaning |
|---|---|
| `-32700` | Parse error |
| `-32600` | Invalid request |
| `-32601` | Method not found |
| `-32602` | Invalid params |
| `-32603` | Internal error |

Custom application errors (code range `-32000` to `-32099`):

| Code | Meaning |
|---|---|
| `-32001` | Buffer not valid |
| `-32002` | No selection available |
| `-32003` | File not found |

## Extension Tool Definitions

The extension registers 4 custom tools with pi:

### `nvim_get_state`

Broad editor context. Calls `state` JSON-RPC method.

- **Parameters:** none
- **Returns:** all buffers, windows, cursor positions, selection summary, current mode

### `nvim_get_buf_content`

Buffer content on demand. Calls `bufContent` JSON-RPC method.

- **Parameters:** `bufnr` (required), `start` (optional), `end` (optional)
- **Returns:** file path, line range, content lines, total line count

### `nvim_get_selection`

Current selection text. Calls `selection` JSON-RPC method.

- **Parameters:** none
- **Returns:** selection text, file path, line range, mode — or null fields if no selection

### `nvim_open_file`

Open a file in neovim. Calls `openFile` JSON-RPC method.

- **Parameters:** `path` (required), `line` (optional), `col` (optional)
- **Returns:** buffer handle and file path confirmation

## File Structure

```
pi-nvim/
├── lua/
│   └── pi-nvim/
│       ├── init.lua           — setup(), open_split(), public API
│       ├── config.lua         — defaults + user option overrides
│       ├── server.lua         — unix socket server (libuv)
│       └── handlers.lua       — JSON-RPC method handlers
├── extension/
│   ├── package.json          — dependencies (@mariozechner/pi-coding-agent, typebox)
│   ├── tsconfig.json          — type checking config
│   ├── src/
│   │   ├── index.ts           — extension entry point
│   │   ├── protocol.ts        — JSON-RPC types, method names, message construction
│   │   ├── socket.ts          — unix socket client with retry logic
│   │   └── tools.ts           — tool definitions
│   └── tests/
│       ├── protocol.test.ts   — message construction, parsing
│       ├── socket.test.ts     — connect, retry, disconnect (mock server)
│       └── tools.test.ts      — each tool with mock socket client
├── plugin/
│   └── pi-nvim.lua            — autocmds, commands
├── tests/
│   ├── minimal_init.lua       — plenary bootstrap
│   └── ...                    — Lua server + handler tests
├── doc/
│   └── pi-nvim.txt           — :help docs
└── docs/
    └── architecture.md        — this file
```

## Future Considerations

These are explicitly **not v1** but are designed-in:

- **Proactive notifications:** The protocol supports JSON-RPC notifications (requests without an `id`). Neovim could push `selectionChanged`, `bufferModified`, `modeChanged` events to the extension.
- **More action methods:** `nvim_set_selection`, `nvim_command`, `nvim_write_buf` — the `openFile` pattern extends naturally.
- **Multiple clients:** The server currently handles one connection. Could track multiple clients by ID.
- **Reconnection:** The extension could detect socket errors and attempt reconnection for transient failures.