import { describe, expect, it } from "vitest";

import { PromptHistory } from "./prompt_history";

describe("PromptHistory", () => {
  it("deduplicates pushes by moving the existing entry to the end", () => {
    const history = new PromptHistory({ maxSize: 5 });

    history.push("first");
    history.push("second");
    history.push("first");

    expect(history.entries.map((entry) => entry.text)).toEqual([
      "second",
      "first",
    ]);
  });

  it("respects maxSize", () => {
    const history = new PromptHistory({ maxSize: 2 });

    history.push("a");
    history.push("b");
    history.push("c");

    expect(history.entries.map((entry) => entry.text)).toEqual(["b", "c"]);
  });

  it("returns null when previous() is not available or already at the start", () => {
    const history = new PromptHistory();

    expect(history.previous("draft")).toBeNull();
  });

  it("stores the preview draft on first previous() and restores it on next()", () => {
    const history = new PromptHistory();

    history.push("old");

    expect(history.previous("draft")).toBe("old");
    expect(history.next()).toBe("draft");
    expect(history.next()).toBeNull();
  });
});
