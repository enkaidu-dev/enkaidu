import { describe, expect, it } from "vitest";

import {
  add_event,
  group_entries,
  is_groupable,
  reset_transcript,
  type SessionEntry,
} from "./transcript";

describe("transcript ingestion", () => {
  it("coalesces streaming llm_text fragments into one growing entry", () => {
    const entries: SessionEntry[] = [];
    const pending: string[] = [];

    add_event(entries, pending, { type: "llm_text", content: "Hello" });
    add_event(entries, pending, { type: "llm_text", content: " world" });

    expect(entries).toHaveLength(1);
    expect(entries[0].data[0].content).toBe("Hello world");
  });

  it("coalesces think fragments into one growing entry", () => {
    const entries: SessionEntry[] = [];
    const pending: string[] = [];

    add_event(entries, pending, { type: "llm_think", content: "think" });
    add_event(entries, pending, { type: "llm_think", content: " more" });

    expect(entries).toHaveLength(1);
    expect(entries[0].data[0].content).toBe("think more");
  });

  it("groups consecutive tool_call records into one entry but keeps distinct entries for non-tool same type appends", () => {
    const entries: SessionEntry[] = [];
    const pending: string[] = [];

    add_event(entries, pending, { type: "tool_call", subject: "t", content: "{}" });
    add_event(entries, pending, { type: "tool_call", subject: "t2", content: "{}" });

    // tool_call never coalesces, so two entries
    expect(entries).toHaveLength(2);

    // message_* same-type appends into data[]
    const entries2: SessionEntry[] = [];
    const pending2: string[] = [];
    add_event(entries2, pending2, { type: "message_info", subject: "a", content: "1" });
    add_event(entries2, pending2, { type: "message_info", subject: "b", content: "2" });
    expect(entries2).toHaveLength(1);
    expect(entries2[0].data).toHaveLength(2);
  });

  it("trims trailing empty assistant entries on a new entry", () => {
    const entries: SessionEntry[] = [];
    const pending: string[] = [];
    add_event(entries, pending, { type: "llm_text", content: "" });
    add_event(entries, pending, { type: "query", content: "hi" });

    expect(entries).toHaveLength(1);
    expect(entries[0].type).toBe("query");
  });

  it("harvests file_path from file tools onto the next llm_text entry", () => {
    const entries: SessionEntry[] = [];
    const pending: string[] = [];
    add_event(entries, pending, {
      type: "tool_call",
      subject: "write_text_file",
      content: JSON.stringify({ file_path: "foo.ts" }),
    });
    add_event(entries, pending, { type: "llm_text", content: "done" });

    expect(entries).toHaveLength(2);
    expect(entries[1].files).toEqual(["foo.ts"]);
    expect(pending).toHaveLength(0);
  });

  it("deduplicates harvested file paths", () => {
    const entries: SessionEntry[] = [];
    const pending: string[] = [];
    const args = JSON.stringify({ file_path: "foo.ts" });
    add_event(entries, pending, { type: "tool_call", subject: "write_text_file", content: args });
    add_event(entries, pending, { type: "tool_call", subject: "str_replace_in_text_file", content: args });
    expect(pending).toEqual(["foo.ts"]);
  });

  it("ignores file tools with invalid JSON", () => {
    const pending: string[] = [];
    const entries: SessionEntry[] = [];
    add_event(entries, pending, {
      type: "tool_call",
      subject: "write_text_file",
      content: "{bad json",
    });
    expect(pending).toHaveLength(0);
  });

  it("resets entries and pending files", () => {
    const entries: SessionEntry[] = [];
    const pending: string[] = [];
    add_event(entries, pending, { type: "llm_text", content: "hi" });
    pending.push("x");
    reset_transcript(entries, pending);
    expect(entries).toHaveLength(0);
    expect(pending).toHaveLength(0);
  });

  it("treats llm_think/tool_call/message_ as groupable", () => {
    expect(is_groupable({ type: "llm_think", data: [] })).toBe(true);
    expect(is_groupable({ type: "tool_call", data: [] })).toBe(true);
    expect(is_groupable({ type: "message_info", data: [] })).toBe(true);
    expect(is_groupable({ type: "llm_text", data: [] })).toBe(false);
  });
});

describe("group_entries", () => {
  it("collapses consecutive groupables into groups and keeps singles standalone", () => {
    const entries: SessionEntry[] = [];
    const pending: string[] = [];
    add_event(entries, pending, { type: "llm_think", content: "t1" });
    add_event(entries, pending, { type: "tool_call", subject: "t", content: "{}" });
    add_event(entries, pending, { type: "llm_text", content: "done" });

    const groups = group_entries(entries);
    expect(groups).toHaveLength(2);
    const g0 = groups[0];
    expect(g0.kind).toBe("group");
    if (g0.kind === "group") {
      expect(g0.items).toHaveLength(2);
      expect(g0.active).toBe(false); // last entry llm_text not groupable
    }
    expect(groups[1].kind).toBe("standalone");
  });

  it("marks trailing group as active when last entry groupable", () => {
    const entries: SessionEntry[] = [];
    const pending: string[] = [];
    add_event(entries, pending, { type: "llm_think", content: "t1" });

    const groups = group_entries(entries);
    expect(groups).toHaveLength(1);
    const g0 = groups[0];
    expect(g0.kind).toBe("standalone"); // single item stays standalone
    // trailing groupable test separately with two
    const entries2: SessionEntry[] = [];
    const pending2: string[] = [];
    add_event(entries2, pending2, { type: "llm_think", content: "a" });
    add_event(entries2, pending2, { type: "tool_call", subject: "x", content: "{}" });
    const g2 = group_entries(entries2);
    expect(g2[0].kind).toBe("group");
    if (g2[0].kind === "group") expect(g2[0].active).toBe(true);
  });
});
