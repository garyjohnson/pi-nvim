/// Tests for JSON-RPC protocol message construction, parsing, and error codes.

import { describe, expect, it } from "bun:test";
import {
  makeRequest,
  parseResponse,
  serializeMessage,
  Methods,
  ErrorCodes,
  type JsonRpcRequest,
  type JsonRpcResponse,
} from "../src/protocol.js";

describe("makeRequest", () => {
  it("creates a valid JSON-RPC request with auto-incrementing id", () => {
    const req = makeRequest(Methods.STATE);
    expect(req.jsonrpc).toBe("2.0");
    expect(req.method).toBe("state");
    expect(req.id).toBeGreaterThan(0);
    expect(req.params).toBeUndefined();
  });

  it("includes params when provided", () => {
    const req = makeRequest(Methods.BUF_CONTENT, { bufnr: 1, start: 10, end: 20 });
    expect(req.params).toEqual({ bufnr: 1, start: 10, end: 20 });
  });

  it("auto-increments ids", () => {
    const req1 = makeRequest(Methods.STATE);
    const req2 = makeRequest(Methods.STATE);
    expect(req2.id).toBeGreaterThan(req1.id);
  });
});

describe("serializeMessage", () => {
  it("serializes a request with a trailing newline", () => {
    const req = makeRequest(Methods.SELECTION);
    const serialized = serializeMessage(req);
    expect(serialized.endsWith("\n")).toBe(true);

    const parsed = JSON.parse(serialized.trim());
    expect(parsed.jsonrpc).toBe("2.0");
    expect(parsed.method).toBe("selection");
  });
});

describe("parseResponse", () => {
  it("parses a successful response", () => {
    const json = JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      result: { protocolVersion: 1, pid: 12345 },
    });
    const resp = parseResponse(json);
    expect(resp.id).toBe(1);
    expect(resp.result).toEqual({ protocolVersion: 1, pid: 12345 });
    expect(resp.error).toBeUndefined();
  });

  it("parses an error response", () => {
    const json = JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      error: { code: -32001, message: "Buffer not valid" },
    });
    const resp = parseResponse(json);
    expect(resp.error).toEqual({ code: -32001, message: "Buffer not valid" });
    expect(resp.result).toBeUndefined();
  });
});

describe("ErrorCodes", () => {
  it("has standard JSON-RPC error codes", () => {
    expect(ErrorCodes.PARSE_ERROR).toBe(-32700);
    expect(ErrorCodes.INVALID_REQUEST).toBe(-32600);
    expect(ErrorCodes.METHOD_NOT_FOUND).toBe(-32601);
    expect(ErrorCodes.INVALID_PARAMS).toBe(-32602);
    expect(ErrorCodes.INTERNAL_ERROR).toBe(-32603);
  });

  it("has custom application error codes", () => {
    expect(ErrorCodes.BUFFER_NOT_VALID).toBe(-32001);
    expect(ErrorCodes.NO_SELECTION).toBe(-32002);
    expect(ErrorCodes.FILE_NOT_FOUND).toBe(-32003);
  });
});