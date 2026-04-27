/// Unix domain socket client for pi-nvim.
/// Connects to the neovim server, sends JSON-RPC requests, and reads responses.

import * as net from "node:net";
import {
  type JsonRpcRequest,
  type JsonRpcResponse,
  type JsonRpcNotification,
  makeRequest,
  serializeMessage,
  parseResponse,
  ErrorCodes,
} from "./protocol.js";

const RECONNECT_ATTEMPTS = 3;
const RECONNECT_DELAY_MS = 200;

type ConnectionState = "disconnected" | "connecting" | "connected";

export class NvimSocketClient {
  private sockPath: string;
  private socket: net.Socket | null = null;
  private state: ConnectionState = "disconnected";
  private buffer = "";
  private pendingRequests = new Map<
    number,
    { resolve: (value: JsonRpcResponse) => void; reject: (reason: Error) => void }
  >();
  private nextId = 1;

  constructor(sockPath: string) {
    this.sockPath = sockPath;
  }

  // ── Connection lifecycle ────────────────────────────────────────────

  async connect(): Promise<void> {
    for (let attempt = 1; attempt <= RECONNECT_ATTEMPTS; attempt++) {
      try {
        await this.attemptConnect();
        this.state = "connected";
        console.log(`[pi-nvim] Connected to neovim at ${this.sockPath}`);
        return;
      } catch (err) {
        console.warn(
          `[pi-nvim] Connection attempt ${attempt}/${RECONNECT_ATTEMPTS} failed: ${err}`,
        );
        if (attempt < RECONNECT_ATTEMPTS) {
          await this.delay(RECONNECT_DELAY_MS);
        }
      }
    }
    this.state = "disconnected";
    throw new Error(
      `[pi-nvim] Failed to connect to neovim at ${this.sockPath} after ${RECONNECT_ATTEMPTS} attempts`,
    );
  }

  private attemptConnect(): Promise<void> {
    return new Promise((resolve, reject) => {
      const socket = new net.Socket();
      socket.setEncoding("utf8");

      socket.on("error", (err) => {
        reject(new Error(`Socket error: ${err.message}`));
        socket.destroy();
      });

      socket.on("connect", () => {
        this.socket = socket;
        this.state = "connected";
        resolve();
      });

      socket.on("data", (data: string | Buffer) => {
        this.handleData(typeof data === "string" ? data : data.toString());
      });

      socket.on("close", () => {
        this.handleDisconnect();
      });

      socket.connect(this.sockPath);
    });
  }

  disconnect(): void {
    if (this.socket) {
      this.socket.destroy();
      this.socket = null;
    }
    this.state = "disconnected";
    this.buffer = "";

    // Reject all pending requests
    for (const [id, pending] of this.pendingRequests) {
      pending.reject(new Error("Socket disconnected"));
      this.pendingRequests.delete(id);
    }
  }

  // ── Request / response ──────────────────────────────────────────────

  async request(method: string, params?: Record<string, unknown>): Promise<JsonRpcResponse> {
    if (this.state !== "connected" || !this.socket) {
      throw new Error("[pi-nvim] Not connected to neovim");
    }

    const id = this.nextId++;
    const request: JsonRpcRequest = {
      jsonrpc: "2.0",
      id,
      method,
      ...(params !== undefined && { params }),
    };

    return new Promise((resolve, reject) => {
      this.pendingRequests.set(id, { resolve, reject });

      const serialized = JSON.stringify(request) + "\n";
      this.socket!.write(serialized, (err) => {
        if (err) {
          this.pendingRequests.delete(id);
          reject(new Error(`Write error: ${err.message}`));
        }
      });
    });
  }

  // ── Data handling ───────────────────────────────────────────────────

  private handleData(data: string): void {
    this.buffer += data;

    while (true) {
      const idx = this.buffer.indexOf("\n");
      if (idx === -1) break;

      const line = this.buffer.substring(0, idx);
      this.buffer = this.buffer.substring(idx + 1);

      if (line.length === 0) continue;

      try {
        const response = parseResponse(line);
        this.handleResponse(response);
      } catch (err) {
        console.error(`[pi-nvim] Failed to parse response: ${err}`);
      }
    }
  }

  private handleResponse(response: JsonRpcResponse): void {
    // Try to match with a pending request
    if (response.id != null && this.pendingRequests.has(response.id)) {
      const pending = this.pendingRequests.get(response.id)!;
      this.pendingRequests.delete(response.id);
      pending.resolve(response);
    }
  }

  private handleDisconnect(): void {
    this.state = "disconnected";
    this.socket = null;

    // Reject all pending requests
    for (const [id, pending] of this.pendingRequests) {
      pending.reject(new Error("Socket disconnected"));
      this.pendingRequests.delete(id);
    }

    console.warn("[pi-nvim] Disconnected from neovim");
  }

  // ── Status ──────────────────────────────────────────────────────────

  get connected(): boolean {
    return this.state === "connected";
  }

  // ── Utility ─────────────────────────────────────────────────────────

  private delay(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }
}