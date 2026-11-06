import { describe, expect, it, vi } from "vitest";

import { MAX_TRIES, run_prompt_session } from "./prompt_flow";

describe("run_prompt_session", () => {
  it("starts once, sends the prompt, and does not drain on success", async () => {
    const ensure_started = vi.fn(async () => {});
    const ask = vi.fn(async (_: string) => true);
    const drain = vi.fn(async () => true);
    const on_reconnect_failed = vi.fn();

    await run_prompt_session({
      query: "hi",
      ensure_started,
      ask,
      drain,
      on_reconnect_failed,
    });

    expect(ensure_started).toHaveBeenCalledOnce();
    expect(ask).toHaveBeenCalledWith("hi");
    expect(drain).not.toHaveBeenCalled();
    expect(on_reconnect_failed).not.toHaveBeenCalled();
  });

  it("drains on a broken prompt and stops at the first success", async () => {
    const ensure_started = vi.fn(async () => {});
    const ask = vi.fn(async () => false);
    const drain = vi.fn().mockResolvedValueOnce(false).mockResolvedValueOnce(true);
    const on_reconnect_failed = vi.fn();

    await run_prompt_session({
      query: "hi",
      ensure_started,
      ask,
      drain,
      on_reconnect_failed,
    });

    expect(drain).toHaveBeenCalledTimes(2);
    expect(on_reconnect_failed).not.toHaveBeenCalled();
  });

  it("calls on_reconnect_failed after MAX_TRIES consecutive failures", async () => {
    const ensure_started = vi.fn(async () => {});
    const ask = vi.fn(async () => false);
    const drain = vi.fn(async () => false);
    const on_reconnect_failed = vi.fn();

    await run_prompt_session({
      query: "hi",
      ensure_started,
      ask,
      drain,
      on_reconnect_failed,
    });

    expect(drain).toHaveBeenCalledTimes(MAX_TRIES);
    expect(on_reconnect_failed).toHaveBeenCalledOnce();
  });

  it("respects a custom max_tries", async () => {
    const ensure_started = vi.fn(async () => {});
    const ask = vi.fn(async () => false);
    const drain = vi.fn(async () => false);
    const on_reconnect_failed = vi.fn();

    await run_prompt_session({
      query: "hi",
      ensure_started,
      ask,
      drain,
      on_reconnect_failed,
      max_tries: 2,
    });

    expect(drain).toHaveBeenCalledTimes(2);
    expect(on_reconnect_failed).toHaveBeenCalledOnce();
  });

  it("succeeds with zero tries left boundary: failure after N should fire", async () => {
    const ensure_started = vi.fn(async () => {});
    const ask = vi.fn(async () => false);
    const drain = vi.fn().mockResolvedValueOnce(true);
    const on_reconnect_failed = vi.fn();

    await run_prompt_session({
      query: "hi",
      ensure_started,
      ask,
      drain,
      on_reconnect_failed,
    });

    expect(drain).toHaveBeenCalledTimes(1);
    expect(on_reconnect_failed).not.toHaveBeenCalled();
  });
});
