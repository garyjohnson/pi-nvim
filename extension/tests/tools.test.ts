/// Tests for tool definitions with a mock socket client.

import { describe, expect, it, beforeEach, afterEach } from "bun:test";
import * as net from "node:net";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { NvimSocketClient } from "../src/socket.js";
import { registerTools } from "../src/tools.js";
import { Methods } from "../src/protocol.js";

// ── Minimal mock ExtensionAPI ─────────────────────────────────────────

interface ToolDefinition {
  name: string;
  label: string;
  description: string;
  parameters: unknown;
  execute: (toolCallId: string, params: unknown, signal: unknown, onUpdate: unknown, ctx: unknown) => Promise<unknown>;
}

function createMockApi(): { api: ExtensionAPI; tools: Map<string, ToolDefinition> } {
  const tools = new Map<string, ToolDefinition>();

  const api = {
    on: () => {},
    registerTool: (def: ToolDefinition) => {
      tools.set(def.name, def);
    },
  } as unknown as ExtensionAPI;

  return { api, tools };
}

// ── Mock server for tool tests ──────────────────────────────────────────

function createMockServer(sockPath: string): net.Server {
  let buffer = "";

  const server = net.createServer((socket) => {
    socket.on("data", (data) => {
      buffer += data.toString();
      while (true) {
        const idx = buffer.indexOf("\n");
        if (idx === -1) break;
        const line = buffer.substring(0, idx);
        buffer = buffer.substring(idx + 1);
        if (line.length === 0) continue;

        try {
          const msg = JSON.parse(line);
          let result: unknown;

          switch (msg.method) {
            case Methods.INITIALIZE:
              result = { protocolVersion: 1, pid: 99999 };
              break;
            case Methods.STATE:
              result = {
                mode: "n",
                currentWin: 1001,
                lastBuffer: 1,
                buffers: [
                  {
                    bufnr: 1,
                    name: "/test/app.lua",
                    listed: true,
                    modified: false,
                    lineCount: 50,
                    filetype: "lua",
                    windows: [1001],
                  },
                ],
                windows: [
                  {
                    winid: 1001,
                    bufnr: 1,
                    cursor: [25, 0],
                    topline: 15,
                    botline: 40,
                  },
                ],
                selection: null,
              };
              break;
            case Methods.BUF_CONTENT:
              result = {
                bufnr: msg.params.bufnr,
                name: "/test/app.lua",
                start: msg.params.start ?? 1,
                end: msg.params.end ?? 50,
                lines: ["local M = {}", "return M"],
                totalLines: 50,
              };
              break;
            case Methods.SELECTION:
              result = {
                mode: "V",
                bufnr: 1,
                name: "/test/app.lua",
                start: [10, 0],
                end: [15, 0],
                text: "selected text here",
              };
              break;
            case Methods.OPEN_FILE:
              result = { bufnr: 2, name: msg.params.path };
              break;
            default:
              result = { error: { code: -32601, message: `Unknown method: ${msg.method}` } };
          }

          const response = { jsonrpc: "2.0", id: msg.id, result };
          socket.write(JSON.stringify(response) + "\n");
        } catch (err) {
          const response = {
            jsonrpc: "2.0",
            id: msg?.id ?? null,
            error: { code: -32603, message: String(err) },
          };
          socket.write(JSON.stringify(response) + "\n");
        }
      }
    });
  });

  try {
    fs.unlinkSync(sockPath);
  } catch {
    // ignore
  }

  server.listen(sockPath);
  return server;
}

// ── Tests ──────────────────────────────────────────────────────────────

describe("Tools", () => {
  const sockPath = path.join(os.tmpdir(), `pi-nvim-tool-test-${process.pid}.sock`);
  let server: net.Server;
  let client: NvimSocketClient;
  let tools: Map<string, ToolDefinition>;

  beforeEach(async () => {
    server = createMockServer(sockPath);
    client = new NvimSocketClient(sockPath);
    await client.connect();

    const mock = createMockApi();
    tools = mock.tools;
    registerTools(mock.api as unknown as ExtensionAPI, client);
  });

  afterEach(() => {
    client.disconnect();
    server.close();
    try {
      fs.unlinkSync(sockPath);
    } catch {
      // ignore
    }
  });

  it("registers 4 tools", () => {
    expect(tools.size).toBe(4);
    expect(tools.has("nvim_get_state")).toBe(true);
    expect(tools.has("nvim_get_buf_content")).toBe(true);
    expect(tools.has("nvim_get_selection")).toBe(true);
    expect(tools.has("nvim_open_file")).toBe(true);
  });

  it("nvim_get_state returns editor state", async () => {
    const tool = tools.get("nvim_get_state")!;
    const result = await tool.execute("id-1", {}, undefined, undefined, undefined);
    expect(result.content[0].type).toBe("text");
    const parsed = JSON.parse(result.content[0].text);
    expect(parsed.mode).toBe("n");
    expect(parsed.currentWin).toBe(1001);
    expect(parsed.buffers).toHaveLength(1);
  });

  it("nvim_get_buf_content returns buffer content", async () => {
    const tool = tools.get("nvim_get_buf_content")!;
    const result = await tool.execute("id-2", { bufnr: 1 }, undefined, undefined, undefined);
    expect(result.content[0].type).toBe("text");
    const parsed = JSON.parse(result.content[0].text);
    expect(parsed.bufnr).toBe(1);
    expect(parsed.name).toBe("/test/app.lua");
  });

  it("nvim_get_selection returns selection text", async () => {
    const tool = tools.get("nvim_get_selection")!;
    const result = await tool.execute("id-3", {}, undefined, undefined, undefined);
    expect(result.content[0].type).toBe("text");
    const parsed = JSON.parse(result.content[0].text);
    expect(parsed.text).toBe("selected text here");
    expect(parsed.mode).toBe("V");
  });

  it("nvim_open_file returns confirmation", async () => {
    const tool = tools.get("nvim_open_file")!;
    const result = await tool.execute("id-4", { path: "/test/new-file.lua" }, undefined, undefined, undefined);
    expect(result.content[0].type).toBe("text");
    const parsed = JSON.parse(result.content[0].text);
    expect(parsed.name).toBe("/test/new-file.lua");
  });

  it("tool returns error when socket is disconnected", async () => {
    client.disconnect();
    const tool = tools.get("nvim_get_state")!;
    const result = await tool.execute("id-5", {}, undefined, undefined, undefined);
    expect(result.content[0].text).toContain("Error");
  });
});