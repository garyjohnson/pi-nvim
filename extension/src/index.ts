/// pi-nvim extension entry point.
/// Connects to the neovim unix socket server and registers custom tools.

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { NvimSocketClient } from "./socket.js";
import { Methods, type InitializeResult } from "./protocol.js";
import { registerTools } from "./tools.js";

export default function (pi: ExtensionAPI) {
  const sockPath = process.env.PI_NVIM_SOCK;

  if (!sockPath) {
    // Not running inside neovim — do nothing
    console.log("[pi-nvim] PI_NVIM_SOCK not set, skipping neovim integration");
    return;
  }

  let client: NvimSocketClient | null = null;

  pi.on("session_start", async (_event, _ctx) => {
    console.log("[pi-nvim] Connecting to neovim at", sockPath);
    client = new NvimSocketClient(sockPath);

    try {
      await client.connect();
    } catch (err) {
      console.error("[pi-nvim] Failed to connect to neovim:", err);
      client = null;
      return;
    }

    // Handshake
    try {
      const response = await client.request(Methods.INITIALIZE);
      if (response.error) {
        console.error("[pi-nvim] Handshake failed:", response.error.message);
        client.disconnect();
        client = null;
        return;
      }

      const result = response.result as InitializeResult;
      console.log(
        `[pi-nvim] Connected to neovim (protocol v${result.protocolVersion}, pid ${result.pid})`,
      );

      // Register tools
      registerTools(pi, client);
    } catch (err) {
      console.error("[pi-nvim] Handshake error:", err);
      client.disconnect();
      client = null;
    }
  });

  pi.on("session_shutdown", async (_event, _ctx) => {
    if (client) {
      console.log("[pi-nvim] Disconnecting from neovim");
      client.disconnect();
      client = null;
    }
  });
}