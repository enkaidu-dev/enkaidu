// Pure helpers for transcript ingestion and grouping.
//
// Extracted from Session.svelte so the entry model (coalescing, file
// harvesting, grouping) can be tested without a Svelte runtime or a
// browser. Session.svelte remains a thin reactive shell that delegates to
// these helpers and passes its $state arrays in by reference; mutations
// here flow straight back into the reactive arrays.
//
// Behavior intentionally mirrors the previous in-component implementation
// exactly; changes to coalescing/grouping should be made here AND covered
// by src/lib/transcript.test.ts.

export type TranscriptEvent = {
  type: string;
  subject?: string | undefined;
  content?: string | undefined;
};

export type SessionData = {
  subject?: string | undefined;
  content?: string | undefined;
};

export type SessionEntry = {
  type: string;
  data: SessionData[];
  // File paths (referenced by file-writing tool calls) that this
  // assistant text entry should offer as viewable files.
  files?: string[] | undefined;
};

export const FILE_TOOLS = new Set([
  "str_replace_in_text_file",
  "write_text_file",
]);

const GROUPABLE = new Set(["llm_think", "tool_call"]);

export function is_groupable(entry: SessionEntry): boolean {
  if (GROUPABLE.has(entry.type)) return true;
  return entry.type.startsWith("message_");
}

// Harvest the file_path from file-modifying tool calls; it rides onto
// the next assistant text entry as a clickable file button.
export function harvest_pending_files(
  ev: TranscriptEvent,
  pending_files: string[],
): void {
  if (
    ev.type === "tool_call" &&
    typeof ev.subject === "string" &&
    FILE_TOOLS.has(ev.subject) &&
    typeof ev.content === "string"
  ) {
    try {
      const parsed = JSON.parse(ev.content) as unknown;
      const path: unknown =
        parsed && typeof parsed === "object" && !Array.isArray(parsed)
          ? (parsed as Record<string, unknown>).file_path
          : undefined;
      if (
        typeof path === "string" &&
        path.length > 0 &&
        !pending_files.includes(path)
      ) {
        pending_files.push(path);
      }
    } catch {
      // args weren't valid JSON — nothing to harvest
    }
  }
}

function check_and_trim_last_entry(entries: SessionEntry[]): void {
  const last = entries.at(-1);
  if (last) {
    if (last.type == "llm_text" || last.type == "llm_think") {
      const content = last.data[0]?.content?.trim();
      if (typeof content === "string" && content.length === 0) {
        entries.pop();
      }
    }
  }
}

// Single ingestion point. Mutates `entries` and `pending_files` in place.
export function add_event(
  entries: SessionEntry[],
  pending_files: string[],
  ev: TranscriptEvent,
): void {
  harvest_pending_files(ev, pending_files);

  const last = entries.at(-1);
  const ev_data: SessionData = { subject: ev.subject, content: ev.content };

  let coalesced = false;
  if (last && last.type == ev.type) {
    if (last.type === "llm_text" || last.type === "llm_think") {
      const content = (last.data[0]?.content || "") + ev_data.content;
      if (!last.data[0]) last.data.push({ content });
      last.data[0].content = content;
      coalesced = true;
    } else if (ev.type !== "tool_call") {
      last.data.push(ev_data);
      coalesced = true;
    }
  }

  if (!coalesced) {
    check_and_trim_last_entry(entries);
    const entry: SessionEntry = { type: ev.type, data: [ev_data] };
    if (ev.type === "llm_text" && pending_files.length > 0) {
      entry.files = pending_files.splice(0);
    }
    entries.push(entry);
  }
}

export function reset_transcript(
  entries: SessionEntry[],
  pending_files: string[],
): void {
  entries.length = 0;
  pending_files.length = 0;
}

export type GroupedEntry =
  | { kind: "group"; items: SessionEntry[]; active: boolean }
  | { kind: "standalone"; entry: SessionEntry };

// Consecutive "agent working" entries collapse into an ActivityGroup.
//
// `running` is the true "agent is mid-run" signal (the app's in-flight
// request flag), and it gates the trailing group's `active` — which drives
// the pulsing step dot.  Inferring "mid-run" from the last entry's type
// alone is wrong: a turn that *ends* on a groupable entry (an interrupt's
// warn message, or a dropped connection that leaves a think block in place)
// would pulse forever, so the type only matters while `running` is true.
export function group_entries(
  entries: SessionEntry[],
  running: boolean,
): GroupedEntry[] {
  const result: GroupedEntry[] = [];
  let current: SessionEntry[] = [];

  const flush = (active: boolean) => {
    if (current.length === 0) return;
    if (current.length === 1) {
      result.push({ kind: "standalone", entry: current[0] });
    } else {
      result.push({ kind: "group", items: current, active });
    }
    current = [];
  };

  for (const entry of entries) {
    if (is_groupable(entry)) {
      current.push(entry);
    } else {
      flush(false);
      result.push({ kind: "standalone", entry });
    }
  }

  const lastEntry = entries.at(-1);
  const lastActive = running && (lastEntry ? is_groupable(lastEntry) : false);
  flush(lastActive);

  return result;
}
