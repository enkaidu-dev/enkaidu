// Pure helpers for *classifying* Enkaidu's NDJSON stream events.
//
// These helpers cover the small pieces of handle_response (in App.svelte)
// that transform one incoming event into zero or more transcript events.
// They are extracted verbatim in spirit so their behavior stays testable and
// App.svelte can remain a thin event dispatcher.

import type { TranscriptEvent } from "./transcript";

export type StreamLlmTextInput = {
  content: string;
  reasoning?: unknown;
};

export type StreamLlmTextFragmentInput = {
  fragment: string;
  reasoning?: unknown;
};

export type FragmentClassification = {
  events: TranscriptEvent[];
  nextThink: boolean;
};

const THINK_START = "<think>";
const THINK_END = "</think>";

// Classifies a non-streaming `llm_text` event. Returns the transcript events
// App.svelte would append.
export function classify_llm_text(
  input: StreamLlmTextInput,
): TranscriptEvent[] {
  const events: TranscriptEvent[] = [];

  if (input.reasoning) {
    events.push({ type: "llm_think", content: input.content });
    return events;
  }

  let content = input.content.trim();
  const think_ix = content.indexOf(THINK_END);
  if (think_ix > 0) {
    const think = content.substring(0, think_ix + 8).trim();
    if (think.length > 0) {
      events.push({ type: "llm_think", content: think });
    }
    content = content.substring(think_ix + 8).trim();
  }

  if (content.length > 0) {
    events.push({ type: "llm_text", content });
  }

  return events;
}

// Classifies a streaming `llm_text_fragment` event. The returned
// `nextThink` flag is the new think-mode state after the fragment. The
// emission order matches App.svelte: think-mode state is updated for the
// start tag before emitting the fragment itself, and the end tag clears it
// only after emitting.
export function classify_llm_text_fragment(
  input: StreamLlmTextFragmentInput,
  think: boolean,
): FragmentClassification {
  if (input.reasoning) {
    return {
      events: [{ type: "llm_think", content: input.fragment }],
      nextThink: think,
    };
  }

  const fragment = input.fragment.trim();
  let nextThink = think;
  if (fragment === THINK_START) nextThink = true;

  const events: TranscriptEvent[] = [
    { type: nextThink ? "llm_think" : "llm_text", content: input.fragment },
  ];

  if (fragment === THINK_END) nextThink = false;

  return { events, nextThink };
}

export function classify_query(
  content: string,
  via_query_queue: boolean = false,
): string {
  const is_command = content.startsWith("/") || content.startsWith("!");
  let type = is_command ? "command" : "query";
  if (via_query_queue) type += "_via_query_queue";
  return type;
}
