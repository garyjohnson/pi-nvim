/// Tests for the NvimSocketClient with a mock unix socket server.

import { describe, expect, it, beforeAll, afterAll } from "bun:test";
import * as net from "node:net";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { NvimSocketClient } from "../src/socket.js";

// ── Mock server ────────────────────────────────────────────────────────

function createMockServer(
  sockPath: string,
  handler: (method: string, params: Record<string, unknown>) => unknown,
): net.Server {
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
          const result = handler(msg.method, msg.params || {});
          const response = {
            jsonrpc: "2.0",
            id: msg.id,
            result,
          };
          socket.write(JSON.stringify(response) + "\n");
        } catch (err) {
          const response = {
            jsonrpc: "2.0",
            id: msg.id ?? null,
            error: { code: -32603, message: String(err) },
          };
          socket.write(JSON.stringify(response) + "\n");
        }
      }
    });
  });

  // Remove stale socket
  try {
    fs.unlinkSync(sockPath);
  } catch {
    // File doesn't exist, that's fine
  }

  server.listen(sockPath);
  return server;
}

// ── Tests ──────────────────────────────────────────────────────────────

describe("NvimSocketClient", () => {
  const sockPath = path.join(os.tmpdir(), `pi-nvim-test-${process.pid}.sock`);
  let server: net.Server;
  let client: NvimSocketClient;

  beforeAll(async () => {
    server = createMockServer(sockPath, (method, params) => {
      if (method === "initialize") {
        return { protocolVersion: 1, pid: 99999 };
      }
      if (method === "state") {
        return {
          mode: "n",
          currentWin: 1001,
          lastBuffer: 1,
          buffers: [],
          windows: [],
          selection: null,
        };
      }
      if (method === "bufContent") {
        return {
          bufnr: params.bufnr,
          name: "/test/file.lua",
          start: 1,
          end: 10,
          lines: ["line 1", "line 2"],
          totalLines: 10,
        };
      }
      return { ok: true };
    });
  });

  afterAll(() => {
    server.close();
    try {
      fs.unlinkSync(sockPath);
    } catch {
      // ignore
    }
  });

  it("connects to a unix socket server", async () => {
    client = new NvimSocketClient(sockPath);
    await client.connect();
    expect(client.connected).toBe(true);
  });

  it("sends initialize and receives response", async () => {
    const response = await client.request("initialize");
    expect(response.result).toEqual({ protocolVersion: 1, pid: 99999 });
    expect(response.error).toBeUndefined();
  });

  it("sends state request and receives response", async () => {
    const response = await client.request("state");
    expect(response.result).toEqual({
      mode: "n",
      currentWin: 1001,
      lastBuffer: 1,
      buffers: [],
      windows: [],
      selection: null,
    });
  });

  it("sends bufContent request with params and receives response", async () => {
    const response = await client.request("bufContent", { bufnr: 1 });
    expect(response.result).toMatchObject({
      bufnr: 1,
      name: "/test/file.lua",
    });
  });

  it("handles sequential requests with different ids", async () => {
    const resp1 = await client.request("state");
    const resp2 = await client.request("state");
    expect(resp1.id).not.toBe(resp2.id);
  });

  it("reports disconnected state after disconnect", () => {
    client.disconnect();
    expect(client.connected).toBe(false);
  });

  it("fails to connect to nonexistent socket", async () => {
    const badClient = new NvimSocketClient("/tmp/nonexistent-pi-nvim-test.sock");
    try {
      await badClient.connect();
      expect.unreachable("Should have thrown");
    } catch (err) {
      expect(err).toBeDefined();
    }
  });
});