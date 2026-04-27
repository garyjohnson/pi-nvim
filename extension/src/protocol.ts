/// Protocol types and message construction for pi-nvim JSON-RPC.

// ── Method names ──────────────────────────────────────────────────────

export const Methods = {
  INITIALIZE: "initialize",
  STATE: "state",
  BUF_CONTENT: "bufContent",
  SELECTION: "selection",
  OPEN_FILE: "openFile",
} as const;

export type MethodName = (typeof Methods)[keyof typeof Methods];

// ── JSON-RPC message types ────────────────────────────────────────────

export interface JsonRpcRequest {
  jsonrpc: "2.0";
  id: number;
  method: string;
  params?: Record<string, unknown>;
}

export interface JsonRpcResponse {
  jsonrpc: "2.0";
  id: number;
  result?: unknown;
  error?: JsonRpcError;
}

export interface JsonRpcError {
  code: number;
  message: string;
}

export interface JsonRpcNotification {
  jsonrpc: "2.0";
  method: string;
  params?: Record<string, unknown>;
}

// ── Request constructors ──────────────────────────────────────────────

let nextId = 1;

export function makeRequest(
  method: string,
  params?: Record<string, unknown>,
): JsonRpcRequest {
  return {
    jsonrpc: "2.0",
    id: nextId++,
    method,
    ...(params !== undefined && { params }),
  };
}

// ── Response shape types (from neovim) ─────────────────────────────────

export interface InitializeResult {
  protocolVersion: number;
  pid: number;
}

export interface BufferInfo {
  bufnr: number;
  name: string;
  listed: boolean;
  modified: boolean;
  lineCount: number;
  filetype: string;
  windows: number[];
}

export interface WindowInfo {
  winid: number;
  bufnr: number;
  cursor: [number, number];
  topline: number;
  botline: number;
}

export interface SelectionInfo {
  mode: string;
  bufnr: number | null;
  name: string | null;
  start: [number, number] | null;
  end: [number, number] | null;
}

export interface StateResult {
  mode: string;
  currentWin: number;
  lastBuffer: number;
  buffers: BufferInfo[];
  windows: WindowInfo[];
  selection: SelectionInfo | null;
}

export interface BufContentResult {
  bufnr: number;
  name: string;
  start: number;
  end: number;
  lines: string[];
  totalLines: number;
}

export interface SelectionResult {
  mode: string;
  bufnr: number | null;
  name: string | null;
  start: [number, number] | null;
  end: [number, number] | null;
  text: string | null;
}

export interface OpenFileResult {
  bufnr: number;
  name: string;
  useSplit?: boolean;
  showDiff?: boolean;
}

// ── Error codes ───────────────────────────────────────────────────────

export const ErrorCodes = {
  PARSE_ERROR: -32700,
  INVALID_REQUEST: -32600,
  METHOD_NOT_FOUND: -32601,
  INVALID_PARAMS: -32602,
  INTERNAL_ERROR: -32603,
  BUFFER_NOT_VALID: -32001,
  NO_SELECTION: -32002,
  FILE_NOT_FOUND: -32003,
} as const;

// ── Serialize / deserialize ──────────────────────────────────────────

export function serializeMessage(msg: JsonRpcRequest | JsonRpcNotification): string {
  return JSON.stringify(msg) + "\n";
}

export function parseResponse(data: string): JsonRpcResponse {
  return JSON.parse(data) as JsonRpcResponse;
}