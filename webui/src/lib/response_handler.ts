// Typed boundary around Enkaidu's NDJSON response stream.
//
// `App.svelte`'s `handle_response` previously parsed each NDJSON line into
// an untyped value and ran a big `switch` over `msg.type` inline. The
// parsing/framing is already owned by `ndjson.ts`; this module owns the
// event-shaped dispatch, so the message vocabulary is a discriminated
// union and the handling logic is testable without a Svelte runtime.
//
// The reactive pieces (`has_content`, `closed`, the `text_thinking`
// streaming flag) stay with the caller: this module reports them through
// the dispatch context / return value rather than reaching into Svelte
// state.

import { read_line_by_line } from "./ndjson";
import { classify_llm_text, classify_llm_text_fragment, classify_query } from "./stream_protocol";
import type { PromptMacro } from "./prompt_tokens";
import type { TranscriptEvent } from "./transcript";
import type { SecurityBanner, InputArg, InputValues } from "../common_types";

export type SystemInfoResponse = {
  type: "system_info";
  host: string;
  cwd: string;
  macros: PromptMacro[];
};

export type SessionInfoResponse = {
  type: "session_info";
  model: string;
};

export type AskForInputsResponse = {
  type: "ask_for_inputs";
  id: string;
  title: string;
  arguments: InputArg[];
  description: string | undefined;
  pre_filled: InputValues | null;
};

export type MessageResponse = {
  type: "message";
  level: string;
  message: string;
  details: string;
};

export type QueryResponse = {
  type: "query";
  content_type: string;
  content: string;
  via_query_queue?: boolean;
};

export type LlmTextResponse = {
  type: "llm_text";
  content: string;
  reasoning?: boolean;
};

export type LlmTextFragmentResponse = {
  type: "llm_text_fragment";
  fragment: string;
  reasoning?: boolean;
};

export type LlmImageUrlResponse = {
  type: "llm_image_url";
  content: string;
};

export type LlmToolCallResponse = {
  type: "llm_tool_call";
  name: string;
  args: unknown;
};

export type HelpResponseResponse = {
  type: "help_response";
  title: string;
  body: string;
};

export type SecurityConfirmationResponse = {
  type: "security_confirmation";
  description: string;
  subjects: string[];
  id: string;
  banner: SecurityBanner | null;
};

export type SecurityPermissionResponse = {
  type: "security_permission";
  description: string;
  subjects: string[];
  id: string;
  banner: SecurityBanner | null;
};

export type SessionResetResponse = { type: "session_reset" };

export type SessionShutdownResponse = { type: "session_shutdown" };

// Unknown / unhandled message kinds fall through to the default arm.
export type UnknownResponse = {
  type: string;
  [key: string]: unknown;
};

export type EnkaiduResponseMessage =
  | SystemInfoResponse
  | SessionInfoResponse
  | AskForInputsResponse
  | MessageResponse
  | QueryResponse
  | LlmTextResponse
  | LlmTextFragmentResponse
  | LlmImageUrlResponse
  | LlmToolCallResponse
  | HelpResponseResponse
  | SecurityConfirmationResponse
  | SecurityPermissionResponse
  | SessionResetResponse
  | SessionShutdownResponse;

export interface ResponseSessionController {
  add_event(ev: TranscriptEvent): void;
  ask_for_inputs(
    id: string,
    title: string,
    input_args: InputArg[],
    description: string | undefined,
    pre_filled: InputValues | null,
  ): void;
  show_security_confirmation(
    description: string,
    subjects: string[],
    id: string,
    banner: SecurityBanner | null,
  ): void;
  show_security_permission(
    description: string,
    subjects: string[],
    id: string,
    banner: SecurityBanner | null,
  ): void;
  reset(): void;
}

export interface ResponsePromptController {
  update_system(host: string, cwd: string, macros: PromptMacro[]): void;
  update_session(modelname: string): void;
}

export interface ResponseDispatchContext {
  session: ResponseSessionController;
  prompt: ResponsePromptController;
  // Reactive scalar sinks live on the caller (Svelte state); they are
  // mutated through these callbacks so the dispatch stays pure-ish.
  set_has_content(value: boolean): void;
  set_closed(value: boolean): void;
}

// Dispatch one parsed message. Returns the next value of the streaming
// `text_thinking` flag (only the `llm_text_fragment` arm changes it).
export function dispatch_response_message(
  msg: EnkaiduResponseMessage,
  ctx: ResponseDispatchContext,
  text_thinking: boolean,
  raw_line: string = JSON.stringify(msg),
): boolean {
  switch (msg.type) {
    case "system_info":
      ctx.prompt.update_system(msg.host, msg.cwd, msg.macros);
      return text_thinking;

    case "session_info":
      ctx.prompt.update_session(msg.model);
      return text_thinking;

    case "ask_for_inputs":
      ctx.session.ask_for_inputs(
        msg.id,
        msg.title,
        msg.arguments,
        msg.description,
        msg.pre_filled,
      );
      return text_thinking;

    case "message":
      ctx.session.add_event({
        type: `message_${msg.level}`,
        subject: msg.message,
        content: msg.details,
      });
      return text_thinking;

    case "query":
      switch (msg.content_type) {
        case "text":
          ctx.session.add_event({
            type: classify_query(msg.content, msg.via_query_queue === true),
            content: msg.content,
          });
          break;
        case "image_url":
          ctx.session.add_event({
            type: "query_image_url",
            content: msg.content,
          });
          break;
        default:
          console.log(`clarion: ${raw_line}`);
          ctx.session.add_event({
            type: "clarion",
            subject: `Unexpected query: ${raw_line}`,
          });
      }
      return text_thinking;

    case "llm_text":
      for (const ev of classify_llm_text({
        content: msg.content,
        reasoning: msg.reasoning,
      })) {
        ctx.session.add_event(ev);
      }
      return text_thinking;

    case "llm_text_fragment": {
      const fragment_classification = classify_llm_text_fragment(
        {
          fragment: msg.fragment,
          reasoning: msg.reasoning,
        },
        text_thinking,
      );
      const next_think = fragment_classification.nextThink;
      for (const ev of fragment_classification.events) {
        ctx.session.add_event(ev);
      }
      return next_think;
    }

    case "llm_image_url":
      ctx.session.add_event({
        type: "llm_image_url",
        content: msg.content,
      });
      return text_thinking;

    case "llm_tool_call":
      ctx.session.add_event({
        type: "tool_call",
        subject: msg.name,
        content: msg.args as string | undefined,
      });
      return text_thinking;

    case "help_response":
      ctx.session.add_event({
        type: "help_response",
        subject: msg.title,
        content: msg.body,
      });
      return text_thinking;

    case "security_confirmation":
      ctx.session.show_security_confirmation(
        msg.description,
        msg.subjects,
        msg.id,
        msg.banner,
      );
      return text_thinking;

    case "security_permission":
      ctx.session.show_security_permission(
        msg.description,
        msg.subjects,
        msg.id,
        msg.banner,
      );
      return text_thinking;

    case "session_reset":
      ctx.session.reset();
      ctx.set_has_content(false);
      return text_thinking;

    case "session_shutdown":
      ctx.set_closed(true);
      return text_thinking;

    default:
      console.log(`clarion: ${raw_line}`);
      ctx.session.add_event({
        type: "clarion",
        content: `Unexpected message: ${raw_line}`,
      });
      return text_thinking;
  }
}

// Read a fetch Response line by line, dispatching each non-empty NDJSON
// line through `dispatch_response_message`. The `text_thinking` streaming
// flag is owned here for the lifetime of one response.
export async function handle_enkaidu_response(
  response: Response,
  ctx: ResponseDispatchContext,
): Promise<void> {
  let text_thinking = false;
  await read_line_by_line(response, (line) => {
    if (line == null || line.length === 0) return;
    const msg = JSON.parse(line) as EnkaiduResponseMessage;
    text_thinking = dispatch_response_message(msg, ctx, text_thinking, line);
  });
}