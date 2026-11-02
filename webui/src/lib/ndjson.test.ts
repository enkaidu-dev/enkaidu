import { describe, expect, it } from "vitest";

import { collect_lines, read_line_by_line } from "./ndjson";

function streamResponse(chunks: string[]): Response {
  const encoder = new TextEncoder();
  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      for (const chunk of chunks) {
        controller.enqueue(encoder.encode(chunk));
      }
      controller.close();
    },
  });
  return new Response(stream, { headers: { "Content-Type": "application/x-ndjson" } });
}

describe("read_line_by_line", () => {
  it("splits a complete single chunk into lines", async () => {
    const resp = streamResponse(["a\nb\nc\n"]);
    const lines = await collect_lines(resp);
    expect(lines).toEqual(["a", "b", "c"]);
  });

  it("buffers a partial last line until it is completed", async () => {
    const resp = streamResponse(["a\nincomplete", "\nrest\n"]);
    const lines = await collect_lines(resp);
    expect(lines).toEqual(["a", "incomplete", "rest"]);
  });

  it("flushes a trailing buffer with no final newline", async () => {
    const resp = streamResponse(["a\nb"]);
    const lines = await collect_lines(resp);
    expect(lines).toEqual(["a", "b"]);
  });

  it("emits null exactly once at EOF via the handler", async () => {
    const resp = streamResponse(["x\n"]);
    const seen: Array<string | null> = [];
    await read_line_by_line(resp, (line) => seen.push(line));
    expect(seen).toEqual(["x", null]);
  });

  it("skips empty lines but still ends with null", async () => {
    // Empty lines are delivered as "" by the reader; the handler decides what to do.
    const resp = streamResponse(["\n\n"]);
    const seen: Array<string | null> = [];
    await read_line_by_line(resp, (line) => seen.push(line));
    expect(seen).toEqual(["", "", null]);
  });

  it("handles an empty body", async () => {
    const resp = streamResponse([]);
    const lines = await collect_lines(resp);
    expect(lines).toEqual([]);
  });
});
