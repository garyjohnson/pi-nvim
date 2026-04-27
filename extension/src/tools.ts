/// Custom tool definitions that call neovim via the socket client.

import { Type } from "typebox";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import type { NvimSocketClient } from "./socket.js";
import {
  Methods,
  type StateResult,
  type BufContentResult,
  type SelectionResult,
  type OpenFileResult,
  type JsonRpcResponse,
  ErrorCodes,
} from "./protocol.js";

// ── Tool registration ─────────────────────────────────────────────────

export function registerTools(pi: ExtensionAPI, client: NvimSocketClient): void {
  // nvim_get_state
  pi.registerTool({
    name: "nvim_get_state",
    label: "Neovim State",
    description:
      "Get the current neovim editor state: all open buffers (file paths, modification status, line counts, filetypes), all windows (with cursor positions and viewport ranges), the current mode, the last focused buffer, and a selection summary (position only, no text content). Use this first to understand what the user is looking at, then drill down with nvim_get_buf_content or nvim_get_selection if needed.",
    promptSnippet: "Check neovim editor state (buffers, windows, selection)",
    promptGuidelines: [
      "Use nvim_get_state when you need to understand what the user is currently looking at or working on in neovim.",
    ],
    parameters: Type.Object({}),
    async execute(_toolCallId, _params, _signal, _onUpdate, _ctx) {
      const result = await sendRequest(client, Methods.STATE);
      return formatResult(result);
    },
  });

  // nvim_get_buf_content
  pi.registerTool({
    name: "nvim_get_buf_content",
    label: "Neovim Buffer Content",
    description:
      "Get the content of a neovim buffer by buffer handle. Returns the file path, line range, and content lines. Use nvim_get_state first to find buffer handles, then call this to read specific buffers or line ranges.",
    promptSnippet: "Read content from a neovim buffer",
    promptGuidelines: [
      "Use nvim_get_buf_content to read file content from neovim buffers. Always call nvim_get_state first to get buffer handles.",
    ],
    parameters: Type.Object({
      bufnr: Type.Number({ description: "Buffer handle (from nvim_get_state)" }),
      start: Type.Optional(Type.Number({ description: "Start line (1-indexed, inclusive). Omit for full buffer." })),
      end: Type.Optional(Type.Number({ description: "End line (1-indexed, inclusive). Omit for full buffer." })),
    }),
    async execute(_toolCallId, params, _signal, _onUpdate, _ctx) {
      const rpcParams: Record<string, unknown> = { bufnr: params.bufnr };
      if (params.start !== undefined) rpcParams.start = params.start;
      if (params.end !== undefined) rpcParams["end"] = params.end;

      const result = await sendRequest(client, Methods.BUF_CONTENT, rpcParams);
      return formatResult(result);
    },
  });

  // nvim_get_selection
  pi.registerTool({
    name: "nvim_get_selection",
    label: "Neovim Selection",
    description:
      "Get the current visual selection in neovim. Returns the selected text, file path, line range, and selection mode. Returns null fields if no selection is active. Use nvim_get_state first to check if a selection exists.",
    promptSnippet: "Get the current visual selection from neovim",
    promptGuidelines: [
      "Use nvim_get_selection when the user refers to selected text or asks about what they have highlighted in neovim.",
    ],
    parameters: Type.Object({}),
    async execute(_toolCallId, _params, _signal, _onUpdate, _ctx) {
      const result = await sendRequest(client, Methods.SELECTION);
      return formatResult(result);
    },
  });

  // nvim_open_file
  pi.registerTool({
    name: "nvim_open_file",
    label: "Neovim Open File",
    description:
      "Open a file in neovim and optionally position the cursor at a specific line and column. Use this to navigate the user's editor to a file you want them to see.",
    promptSnippet: "Open a file in the user's neovim editor",
    promptGuidelines: [
      "Use nvim_open_file to navigate the user's editor to a relevant file, such as when you want them to review a change or see a specific location.",
    ],
    parameters: Type.Object({
      path: Type.String({ description: "File path to open" }),
      line: Type.Optional(Type.Number({ description: "Line number to position cursor (1-indexed)" })),
      col: Type.Optional(Type.Number({ description: "Column number to position cursor (0-indexed)" })),
    }),
    async execute(_toolCallId, params, _signal, _onUpdate, _ctx) {
      const rpcParams: Record<string, unknown> = { path: params.path };
      if (params.line !== undefined) rpcParams.line = params.line;
      if (params.col !== undefined) rpcParams.col = params.col;

      const result = await sendRequest(client, Methods.OPEN_FILE, rpcParams);
      return formatResult(result);
    },
  });
}

// ── Helpers ────────────────────────────────────────────────────────────

async function sendRequest(
  client: NvimSocketClient,
  method: string,
  params?: Record<string, unknown>,
): Promise<JsonRpcResponse> {
  try {
    return await client.request(method, params);
  } catch (err) {
    return {
      jsonrpc: "2.0",
      id: 0,
      error: {
        code: ErrorCodes.INTERNAL_ERROR,
        message: `Failed to communicate with neovim: ${err}`,
      },
    };
  }
}

function formatResult(response: JsonRpcResponse): {
  content: Array<{ type: "text"; text: string }>;
  details: Record<string, unknown>;
} {
  if (response.error) {
    return {
      content: [
        {
          type: "text",
          text: `Error: ${response.error.message} (code ${response.error.code})`,
        },
      ],
      details: { error: response.error },
    };
  }

  return {
    content: [
      {
        type: "text",
        text: JSON.stringify(response.result, null, 2),
      },
    ],
    details: { result: response.result },
  };
}