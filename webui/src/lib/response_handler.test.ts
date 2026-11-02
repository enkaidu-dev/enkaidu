import { describe, expect, it, vi } from "vitest";

import { dispatch_response_message, handle_enkaidu_response } from "./response_handler";
import type { ResponseDispatchContext } from "./response_handler";

function make_context() {
  const session = {
    add_event: vi.fn(),
    ask_for_inputs: vi.fn(),
    show_security_confirmation: vi.fn(),
    show_security_permission: vi.fn(),
    reset: vi.fn(),
  };
  const prompt = {
    update_system: vi.fn(),
    update_session: vi.fn(),
  };
  const ctx: ResponseDispatchContext = {
    session,
    prompt,
    set_has_content: vi.fn(),
    set_closed: vi.fn(),
  };
  return { session, prompt, ctx };
}

describe("response dispatch", () => {
  it("routes system and session info", () => {
    const { prompt, ctx } = make_context();
    expect(
      dispatch_response_message(
        { type: "system_info", host: "h", cwd: "/tmp", macros: [] },
        ctx,
        false,
      ),
    ).toBe(false);
    expect(prompt.update_system).toHaveBeenCalledWith("h", "/tmp", []);

    dispatch_response_message(
      { type: "session_info", model: "m" },
      ctx,
      false,
    );
    expect(prompt.update_session).toHaveBeenCalledWith("m");
  });

  it("routes ask_for_inputs and message events", () => {
    const { session, ctx } = make_context();
    const args = [{ type: "string", name: "x" }];
    dispatch_response_message(
      {
        type: "ask_for_inputs",
        id: "id",
        title: "t",
        arguments: args,
        description: "d",
        pre_filled: null,
      },
      ctx,
      false,
    );
    expect(session.ask_for_inputs).toHaveBeenCalledWith(
      "id",
      "t",
      args,
      "d",
      null,
    );

    dispatch_response_message(
      {
        type: "message",
        level: "info",
        message: "subj",
        details: "body",
      },
      ctx,
      false,
    );
    expect(session.add_event).toHaveBeenCalledWith({
      type: "message_info",
      subject: "subj",
      content: "body",
    });
  });

  it("classifies and routes query variants", () => {
    const { session, ctx } = make_context();
    dispatch_response_message(
      { type: "query", content_type: "text", content: "/help", via_query_queue: true },
      ctx,
      false,
    );
    expect(session.add_event).toHaveBeenCalledWith({
      type: "command_via_query_queue",
      content: "/help",
    });

    dispatch_response_message(
      { type: "query", content_type: "image_url", content: "http://img" },
      ctx,
      false,
    );
    expect(session.add_event).toHaveBeenCalledWith({
      type: "query_image_url",
      content: "http://img",
    });

    dispatch_response_message(
      { type: "query", content_type: "nope", content: "x" },
      ctx,
      false,
    );
    expect(session.add_event).toHaveBeenCalledWith({
      type: "clarion",
      subject: "Unexpected query: " + JSON.stringify({ type: "query", content_type: "nope", content: "x" }),
    });
  });

  it("routes llm text and fragments, updating think state", () => {
    const { session, ctx } = make_context();
    dispatch_response_message(
      { type: "llm_text", content: "hello", reasoning: false },
      ctx,
      false,
    );
    expect(session.add_event).toHaveBeenCalled();

    const next = dispatch_response_message(
      { type: "llm_text_fragment", fragment: "a", reasoning: false },
      ctx,
      false,
    );
    expect(typeof next).toBe("boolean");
    expect(session.add_event).toHaveBeenCalled();
  });

  it("routes remaining simple message types", () => {
    const { session, ctx } = make_context();
    const cases = [
      { msg: { type: "llm_image_url", content: "u" }, expected: { type: "llm_image_url", content: "u" } },
      { msg: { type: "llm_tool_call", name: "tool", args: "{}" }, expected: { type: "tool_call", subject: "tool", content: "{}" } },
      { msg: { type: "help_response", title: "h", body: "b" }, expected: { type: "help_response", subject: "h", content: "b" } },
    ];
    for (const c of cases) {
      session.add_event.mockClear();
      dispatch_response_message(c.msg as never, ctx, false);
      expect(session.add_event).toHaveBeenCalledWith(c.expected);
    }
  });

  it("routes security, reset, and shutdown messages", () => {
    const { session, ctx } = make_context();
    const banner = { safe: true, message: "ok" };
    dispatch_response_message(
      {
        type: "security_confirmation",
        description: "d",
        subjects: ["s"],
        id: "1",
        banner,
      },
      ctx,
      false,
    );
    expect(session.show_security_confirmation).toHaveBeenCalledWith("d", ["s"], "1", banner);

    dispatch_response_message(
      {
        type: "security_permission",
        description: "d",
        subjects: ["s"],
        id: "1",
        banner,
      },
      ctx,
      false,
    );
    expect(session.show_security_permission).toHaveBeenCalledWith("d", ["s"], "1", banner);

    dispatch_response_message({ type: "session_reset" }, ctx, false);
    expect(session.reset).toHaveBeenCalled();
    expect(ctx.set_has_content).toHaveBeenCalledWith(false);

    dispatch_response_message({ type: "session_shutdown" }, ctx, false);
    expect(ctx.set_closed).toHaveBeenCalledWith(true);
  });

  it("falls through to a clarion for unknown message types", () => {
    const { session, ctx } = make_context();
    dispatch_response_message(
      { type: "mystery" } as never,
      ctx,
      false,
    );
    expect(session.add_event).toHaveBeenCalledWith({
      type: "clarion",
      content: 'Unexpected message: {"type":"mystery"}',
    });
  });
});

describe("handle_enkaidu_response", () => {
  it("reads non-empty lines and ignores empty lines", async () => {
    const { session, ctx } = make_context();
    const body = [
      JSON.stringify({ type: "session_info", model: "gpt" }),
      "",
      JSON.stringify({ type: "session_shutdown" }),
    ].join("\n");
    await handle_enkaidu_response(new Response(body), ctx);
    expect(session.add_event).not.toHaveBeenCalled();
    expect(ctx.set_closed).toHaveBeenCalled();
  });
});
