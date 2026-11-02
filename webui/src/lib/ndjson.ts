// Pure NDJSON (newline-delimited JSON) line reader.
//
// Extracted from App.svelte so the framing logic (partial-line buffering,
// trailing buffer flush, EOF sentinel) is testable without a Svelte runtime.
// App.svelte's handle_response still owns the event-shaped dispatch; this
// module only turns a fetch Response into individual lines.

export async function read_line_by_line(
  response: Response,
  handler: (line: string | null) => void,
): Promise<void> {
  const reader = response.body?.getReader();
  if (!reader) {
    handler(null);
    return;
  }

  const decoder = new TextDecoder();
  let buffer = "";

  while (true) {
    const { done, value } = await reader.read();
    if (done) {
      if (buffer) handler(buffer);
      handler(null);
      break;
    }
    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split("\n");
    buffer = lines.pop() || "";
    lines.forEach((line) => handler(line));
  }
}

// Convenience for tests: collect a Response into an array of lines.
export async function collect_lines(response: Response): Promise<string[]> {
  const lines: string[] = [];
  await read_line_by_line(response, (line) => {
    if (line !== null) lines.push(line);
  });
  return lines;
}
