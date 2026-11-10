import { describe, expect, it } from "vitest";

import {
  classify_llm_text,
  classify_llm_text_fragment,
  classify_query,
} from "./stream_protocol";

describe("classify_llm_text", () => {
  it("routes reasoning input to llm_think", () => {
    expect(
      classify_llm_text({ content: "answer", reasoning: true }),
    ).toEqual([{ type: "llm_think", content: "answer" }]);
  });

  it("splits a leading think block out of non-reasoning input", () => {
    const input = {
      content: "</think> tail".replace("</think>", "<think></think> tail".slice(0, 8) + " body</think>")
    };
    // Use a constructed source to avoid zero-width ambiguity in the test itself.
    const tag = "</think>";
    const src = "<think>inner</think> outer";
    const events = classify_llm_text({ content: src });
    // end tag length is 8
    expect(events).toEqual([
      { type: "llm_think", content: "<think>inner</think>" },
      { type: "llm_text", content: "outer" },
    ]);
  });

  it("returns no llm_text event when the body is empty", () => {
    const src = "<think>inner</think>";
    const events = classify_llm_text({ content: src });
    expect(events).toEqual([{ type: "llm_think", content: "<think>inner</think>" }]);
  });

  it("passes plain text through unchanged (trimmed)", () => {
    expect(classify_llm_text({ content: "  hi  " })).toEqual([
      { type: "llm_text", content: "hi" },
    ]);
  });

  it("ignores negative think index appropriately", () => {
    // indexOf returns -1 when absent; > 0 guard means -1 is ignored.
    expect(classify_llm_text({ content: "</think> alone" })).toEqual([
      { type: "llm_text", content: "</think> alone" },
    ]);
  });
});

describe("classify_llm_text_fragment", () => {
  it("start tag switches think mode on before emitting", () => {
    const result = classify_llm_text_fragment(
      { fragment: "<think>" },
      false,
    );
    expect(result).toEqual({
      events: [{ type: "llm_think", content: "<think>" }],
      nextThink: true,
    });
  });

  it("end tag routes the fragment to think, then clears mode", () => {
    const result = classify_llm_text_fragment(
      { fragment: "</think>" },
      true,
    );
    expect(result).toEqual({
      events: [{ type: "llm_think", content: "</think>" }],
      nextThink: false,
    });
  });

  it("reasoning fragments stay in think mode", () => {
    const result = classify_llm_text_fragment(
      { fragment: "piece", reasoning: true },
      false,
    );
    expect(result).toEqual({
      events: [{ type: "llm_think", content: "piece" }],
      nextThink: false,
    });
  });

  it("passes through the raw fragment content", () => {
    const result = classify_llm_text_fragment(
      { fragment: "  spaced  " },
      false,
    );
    expect(result.events[0].content).toBe("  spaced  ");
  });
});

describe("classify_query", () => {
  it("classifies slash and bang as commands", () => {
    expect(classify_query("/help")).toBe("command");
    expect(classify_query("!macro")).toBe("command");
  });

  it("classifies plain text as query", () => {
    expect(classify_query("hello")).toBe("query");
  });

  it("appends via_query_queue when requested", () => {
    expect(classify_query("hello", true)).toBe("query_via_query_queue");
    expect(classify_query("/help", true)).toBe("command_via_query_queue");
  });
});
