# SCOPE — Enkaidu

Working roadmap of features and capability additions. Intended to accumulate
over time; each feature gets its own section with rationale, design proposal,
open decisions, and an implementation checklist.

Status legend check boxes: `- [ ]` pending · `- [~]` in progress · `- [x]` done.

## Feature Index

No.|Feature                                                                           |Status  
---|----------------------------------------------------------------------------------|--------
1  |[Web UI ↔ Enkaidu connection resilience](#1-web-ui--enkaidu-connection-resilience)|Proposed

---

# 1. Web UI ↔ Enkaidu Connection Resilience

**Scope boundary:** the web UI (Svelte SPA in `webui/src`) up to the wire/
protocol boundary (the `WUI::Main` routes, `EventRenderer`, `render_events/*`,
and a new durable event journal in `WUI::Main`). **Agent-internal changes to
`Session` / `Runtime` / `LLM::Chat` are explicitly out of scope** — this feature
must be buildable purely at the renderer/wire layer.

**Originating motivation:** if a user closes the web UI tab (or it reloads, or a
stream drops mid-run), the UI currently loses its transcript and its connection,
and cannot recover — even though Enkaidu keeps the session history alive. We want
the UI to be recoverable: reopening a tab should restore the conversation, and a
dropped in-flight prompt should be resumable.

## 1.1 What Enkaidu already provides (no agent changes needed)

The following already exist in memory and are sufficient foundations:

- **A stable session id** — `Session#id` is a `UUID.v7` (`session.cr`). Not yet
  sent anywhere on the wire.
- **A JSON-serializable transcript** — the conversation log lives in
  `session.chat` (`LLM::OpenAI::History#messages`) and already round-trips via
  `Chat#save` / `Chat#load`.
- **Events that serialize** — every `Render::Event` already `to_json` cleanly
  (`type` + `time` + payload), so a held event can be re-emitted verbatim.

Recovery is therefore achievable; the work is **exposing** what already exists,
plus a few boundary additions.

## 1.2 Current-state gaps

Gaps that block resilience (all at the boundary or in the SPA, with evidence):

Gap                           |Evidence                                                                                                                                                                                          
------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
No identity on the wire       |`Session.get_id()` returns `"not_applicable"`; `new_prompt_request` hard-codes `sessionId`; no request headers carry a client/session id.                                                         
No per-event cursor           |Events carry only `type` + `time`. No sequence number, no monotonic cursor anywhere.                                                                                                              
No durable event retention    |The render-event buffer is a destructive `Deque` (`shift?` via `gather_queue_events`); already-delivered events are gone on disconnect. `GET /api/drain` recovers only what is currently buffered.
No frontend recovery lifecycle|No `beforeunload` / `visibilitychange` / `online` / `offline` / `AbortController` / `setTimeout` / storage anywhere in `webui/src`.                                                               
No clean-completion signal    |"The turn is over" is detected only by stream closure, indistinguishable from a dropped connection. No `turn_end` / `stopReason` branch in `handle_response`.                                     
Weak retry                    |A one-shot, no-backoff 3× `GET /api/drain`, reached only for prompt-stage failures.                                                                                                               
Stale UI state on failure     |`has_content` is never cleared on failure; `check_if_started` (first-turn path) has no `catch`, so a failed `/api/start` becomes an unhandled rejection the retry logic never sees.               

Two blockers that must be resolved for a robust design:

- **JSON-discriminator table is out of sync** (`render_events/event.cr`): the
  `use_json_discriminator "type"` table lists two non-existent classes
  (`shell_confirmation` / `ShellConfirmation`, `session_update` / `SessionUpdate`)
  and omits five real types (`llm_image_url`, `security_confirmation`,
  `ask_for_inputs`, `system_info`, `session_reset`). Fine for re-emitting held
  JSON, but it breaks any path that re-parses stored events — so a
  store-then-reparse journal requires the fix first.
- **Blocking interactions deadlock on disconnect.** Security confirmations and
  input asks block the single resident main fiber on unbuffered, timeout-free
  channels (`WUI::Main` / `EventRenderer`). A disconnected tab never posts an
  answer, so the channel blocks forever, the `pending_*` entry is orphaned, and
  the whole server wedges.

## 1.3 Capability catalog

The kinds of resilience the web UI needs (the tab-close/reload case is the
centre item, C1):

#            |Capability                                                            |Today                                                                                          
-------------|----------------------------------------------------------------------|-----------------------------------------------------------------------------------------------
C1           |Transcript recovery on load / tab reopen                              |None — reload wipes transcript + connection; nothing reconstructs it                           
C2           |Session identity + per-event cursor on the wire                       |Neither — `sessionId="not_applicable"`, no sequence                                            
C3           |Clean-completion vs. dropped-stream detection                         |Undetectable — both look like "stream closed"                                                  
C4           |Reconnect with backoff on a dropped in-flight prompt                  |One-shot no-backoff 3× drain, prompt-stage only                                                
C5           |Mid-run tab close → reattach to the live stream you missed events from|Not possible — execution is serialized; a reconnected client can't reattach to a running prompt
C6           |Unanswered blocking interaction survives a disconnect                 |It deadlocks the worker fiber; no timeout, no re-presentation                                  
C7           |Idempotent re-injection (no double-render on replay)                  |Unsafe — `Session.add_event` coalesces onto the live tail and can't tell old from new events   
C8           |Liveness / visibility recovery                                        |None — no `visibilitychange` / `online` / `focus` triggers recovery                            
C9 (optional)|Client-side short-term cache (offline-reload shows last state)        |None                                                                                           

## 1.4 Design proposal

### 1.4.1 Design principle

Run recovery through the **exact same event pipeline the live stream already
uses**, so the frontend needs almost no new render code. The server does not hand
over a different "history format" — it re-emits the **same render-event JSON the
UI already understands**. The live path and the replay path converge on one
`handle_response` / `add_event`. Replay is therefore a *projection from the event
history* the renderer produces, not a re-derivation of the conversation log.

### 1.4.2 Wire / protocol surface (new or changed, renderer layer only)

Item                      |Proposal                                                                                                                                                                                                                                                                                |Capability
--------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------
Session identity          |Add a `sessionId` field to `system_info` (or a new `session_init`). The SPA stores it and echoes it on every later request via an `X-Enkaidu-Session` header (or a body field). Surfaces the existing `Session#id`.                                                                     |C2        
Per-event cursor          |Assign a monotonic per-session `seq` in `EventRenderer#post_event`, carried on every `Render::Event`. The SPA tracks `last_seq`; the server can serve "since N". Makes re-injection idempotent.                                                                                         |C2, C7    
Terminal event            |Emit a `turn_end` (or reuse ACP `stopReason`) as the last event per turn so the SPA can distinguish clean completion from a dropped stream.                                                                                                                                             |C3        
Durable event journal     |`EventRenderer` keeps an append-only journal (a second buffer alongside the destructive `Deque`, or a `Recorder`-style tap) of every emitted event for the session's lifetime. The source a replay re-emits.                                                                            |C1, C4, C5
Restore / replay request  |`GET /api/replay?since=<seq>` (or a `restore` flag on `GET /api/start`) streamed as NDJSON: journal events with `seq > since`, terminated by the terminal event. `since` absent or `0` = full restore. For an in-flight prompt, append currently-buffered/live events after the journal.|C1, C4, C5
Keep existing event shapes|Replay re-emits the same `Render::Event` types via `to_json`; no new client render branches.                                                                                                                                                                                            |—         

### 1.4.3 Frontend changes (within `webui/src`)

- A small **`ConnectionManager`** (module or logic in `App.svelte`) that owns the
  `sessionId`, the `last_seq` cursor, a backoff loop, and the
  `visibilitychange` / `pagehide` / `online` / `offline` / `focus` listeners. On
  load and on every detected drop while a request is in flight, it calls
  `/api/replay?since=last_seq` and runs the returned events through the existing
  `handle_response` / `add_event` pipeline.
- **`Session.svelte` idempotent replay injection** — a `restore(events)` path that
  *resets and re-injects in order* (or dedups by `seq`) instead of coalescing
  onto the live tail. This is the one real risk C7 poses, so `add_event`'s
  coalescing needs a "fresh reconstruction vs. live append" mode.
- **`utilities.ts` gains** an `AbortController` + per-request timeout, a
  status-aware fetch (a non-2xx empty body is currently a silent success), and a
  way to carry the session header and the `since` param.
- **Close the small liveness gaps:** a `catch` around `check_if_started`
  (first-turn path currently throws an unhandled rejection the retry loop never
  sees); clear `has_content` on failure so layout isn't stuck in a half-state.
- **Optional C9:** snapshot the transcript to `sessionStorage` / `IndexedDB` on
  each append for offline-reload progressive UX, with the server authoritative on
  replay.

### 1.4.4 Boundary contracts the Enkaidu side must honor (renderer layer, not agent core)

- The event journal is durable enough to serve disconnected events; the
  per-event `seq` is assigned; `Session#id` is surfaced into the init event.
- **Fix the `render_events/event.cr` `use_json_discriminator` table** — the one
  prerequisite for any path that re-parses stored events.
- **Blocking interactions become disconnect-aware** — a finite lifetime/timeout,
  and on a closed tab the pending confirmation/input is left resumable and
  re-emittable during a restore, so a reconnecting tab can still answer it rather
  than the server wedging.

## 1.5 Open decisions (to resolve before final design)

1. **In-flight prompt when the tab fully closes:** should it keep running
   server-side and be reattachable (needs the full durable journal, C5/Phase 2),
   or is it acceptable that a fully-closed tab abandons running work and only
   the *completed* conversation is restored (Phase 1, leaner)? The originating
   phrasing ("re-play the session history") reads as the latter being the core
   ask; full live reattach is the nice-to-have.
2. **Journal lifetime:** keep every event for the session's lifetime
   (growth/backpressure question), a bounded ring buffer, or reconstruct from
   `chat.history` only. This sets how much live catch-up C5 can offer.
3. **Blocking-interaction disconnect policy:** auto-approve/deny on timeout, or
   suspend-and-resume on reconnect?
4. **Identity model now vs. later:** one in-memory session per process, or do we
   foresee multiple / named sessions in the web UI (the ACP `NewSession` /
   `LoadSession` paths exist but are unused)?

## 1.6 Plan / checklist

Phased so each phase is independently valuable. Phase 0 unblocks everything.

**Phase 0 — Unblockers (cheap, prerequisite)**
- [ ] Surface `Session#id` on the wire (augment `system_info` or new `session_init`).
- [ ] Assign a monotonic per-session `seq` in `EventRenderer#post_event`; carry it on every `Render::Event`.
- [ ] Fix the `render_events/event.cr` `use_json_discriminator` table (rename the two bad entries; add the five missing types).
- [ ] Frontend: store `sessionId` and echo it on subsequent requests; track `last_seq`.

**Phase 1 — Transcript recovery on load / tab reopen (originating motivation)**
- [ ] Backend: durable event journal in `EventRenderer` (append-only alongside the `Deque`, or a `Recorder` tap).
- [ ] Backend: `GET /api/replay?since=<seq>` (or `restore` flag on `/api/start`) streaming journal events as NDJSON, terminated by the terminal event.
- [ ] Backend: emit a terminal `turn_end` event at end of each turn.
- [ ] Frontend: `ConnectionManager` module — `sessionId`, `last_seq`, backoff loop, lifecycle listeners.
- [ ] Frontend: on load (and on `pagehide`/`visibilitychange`/`focus`/`online`), call `/api/replay?since=last_seq` and run events through `handle_response`/`add_event`.
- [ ] Frontend: `Session.svelte` idempotent `restore(events)` path (reset-and-reinject or dedup by `seq`); gate `add_event` coalescing on a "fresh reconstruction vs. live append" flag.
- [ ] Frontend: `utilities.ts` `AbortController` + timeout + status-aware fetch + session header + `since` param.
- [ ] Fix liveness gaps: `catch` around `check_if_started`; clear `has_content` on failure.
- [ ] Acceptance: full close + reopen of the tab shows the complete prior transcript.

**Phase 2 — Mid-run survival (optional, depends on decision 1)**
- [ ] Backend: on `/api/replay` for an in-flight prompt, append currently-buffered/live events after the journal; allow a reconnected client to reattach.
- [ ] Frontend: after a mid-stream drop, reconnect with backoff and resume since `last_seq` until the terminal event.
- [ ] Acceptance: close the tab mid-prompt, reopen, and the run completes with the missed events filled in.

**Phase 3 — Disconnect-aware blocking interactions (C6)**
- [ ] Timeout or connection-tie for `pending_confirmations` / `pending_inputs` so a closed tab no longer wedges the main fiber.
- [ ] On restore, re-emit any unanswered confirmation/input so a reconnected tab can still answer it.
- [ ] Choose the disconnect policy (open decision 3).

**Phase 4 — Polish**
- [ ] Client-side short-term cache (`sessionStorage` / `IndexedDB`) for offline-reload progressive UX (optional C9).
- [ ] Connection liveness heartbeat / staleness detector.

## 1.7 Out of scope

- Agent-internal changes to `Session` / `Runtime` / `LLM::Chat` (the
  conversation log, prompt flow, and tool-consumption machinery are not to be
  redesigned — only exposed at the boundary).
- Client-side routing / multi-view app (not requested here).
- Full global-state store or WebSocket transport (current NDJSON-over-HTTP model is
  kept; see `tmp_WEBUI.md`, §6).

## 1.8 References

- `webui/tmp_WEBUI.md` — architecture reference (transport, components, event
  types, channels/fibers).
- `webui/src/App.svelte` — orchestrator, `handle_response` dispatcher, retry/drain.
- `webui/src/lib/Session.svelte` — `entries`, `add_event` coalescing, `get_id`.
- `webui/src/lib/Promptbar.svelte` — loading/waiting-dots state, `update(host,cwd)`.
- `webui/src/utilities.ts` — `enkaidu_get_request` / `enkaidu_post_request`.
- `src/enkaidu/wui/main.cr` — `WUI::Main`, route registration, channel/fiber wiring.
- `src/enkaidu/wui/event_renderer.cr` — `EventRenderer#post_event`, pending_* maps.
- `src/enkaidu/wui/render_events/event.cr` — discriminator table (the fix target).
- `src/enkaidu/session.cr` — `Session#id` (UUID.v7), `@chat`.
- `src/llm/openai/chat.cr` / `history.cr` — JSON transcript (`save`/`load`).
