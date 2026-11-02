// Pure (dependency-injected) helpers for Enkaidu's prompt request flow.
//
// Extracted from App.svelte so the reconnect policy (try draining up to
// MAX_TRIES times before surfacing a failure) can be exercised without a
// Svelte runtime. App.svelte keeps the reactive `handling_request` flag,
// the beforeunload guard, and focus restoration; this module owns the
// sequencing of start → prompt → drain retries.

export const MAX_TRIES = 3;

export type RunPromptSessionOptions = {
  query: string;
  // Establish the channel (fired once per prompt).
  ensure_started: () => Promise<void>;
  // Send the prompt; true = stream completed, false = connection broke.
  ask: (query: string) => Promise<boolean>;
  // Ask Enkaidu to drain remaining events and re-open the stream.
  drain: () => Promise<boolean>;
  // Called exactly once when `drain` fails `max_tries` times in a row.
  on_reconnect_failed: () => void;
  max_tries?: number;
};

// Send one prompt through the full Enkaidu channel, recovering from a
// dropped connection with up to `max_tries` drain attempts. Mirrors the
// previous inline implementation in App.svelte.
export async function run_prompt_session(
  options: RunPromptSessionOptions,
): Promise<void> {
  const maxTries = options.max_tries ?? MAX_TRIES;

  await options.ensure_started();

  if (await options.ask(options.query)) {
    return;
  }

  // The prompt's stream broke; Enkaidu may still be producing events,
  // so reconnect and drain up to MAX_TRIES times.
  let tries = 0;
  while (tries < maxTries) {
    if (await options.drain()) break;
    tries += 1;
  }

  if (tries >= maxTries) {
    options.on_reconnect_failed();
  }
}
