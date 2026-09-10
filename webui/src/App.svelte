<script lang="ts">
  import { onMount } from "svelte";
  import * as Acp from "./acp_schema_types";

  import { enkaidu_post_request, enkaidu_get_request } from "./utilities";

  import Promptbar from "./lib/Promptbar.svelte";
  import Session from "./lib/Session.svelte";
  import FilePanel from "./lib/FilePanel.svelte";
  // import Sidebar from "./lib/Sidebar.svelte";

  let session: Session;
  let prompt: Promptbar;

  let started = false;
  let handling_request = $state(false);
  let has_content = $state(false);

  // ---- File side panel -----------------------------------------------------
  // The path currently shown in the panel (null = closed), plus the fetched
  // content / loading / error state for it.
  let open_file: string | null = $state(null);
  let file_body = $state("");
  let file_loading = $state(false);
  let file_error = $state("");

  // The split-view panel width the user can drag to resize (pixels). It starts
  // at half the window and is remembered across open/close cycles.
  let main_ref: HTMLElement;
  let file_panel_width = $state(Math.round(window.innerWidth / 2));

  // Keep a sensible floor for each side so neither the transcript nor the panel
  // can be squeezed past 20rem.
  const MIN_PANEL = 320;
  const MIN_LEFT = 320;

  function clamp_width(w: number): number {
    const total = main_ref ? main_ref.clientWidth : window.innerWidth;
    return Math.max(MIN_PANEL, Math.min(total - MIN_LEFT, w));
  }

  // Begin a pointer drag on the resizer; track the cursor until release and
  // recompute the panel width from the container's right edge.
  function start_resize(e: PointerEvent) {
    e.preventDefault();
    if (!main_ref) return;
    const start = main_ref.getBoundingClientRect();

    function on_move(ev: PointerEvent) {
      // The panel is the right column, so its width is the distance from the
      // container's right edge to the cursor.
      file_panel_width = clamp_width(start.right - ev.clientX);
    }
    function on_up() {
      window.removeEventListener("pointermove", on_move);
      window.removeEventListener("pointerup", on_up);
      document.body.classList.remove("enkaidu-resizing");
    }
    document.body.classList.add("enkaidu-resizing");
    window.addEventListener("pointermove", on_move);
    window.addEventListener("pointerup", on_up);
  }

  // Reset the split back to an even 50/50 divide (e.g. on a double-click).
  function reset_width() {
    const total = main_ref ? main_ref.clientWidth : window.innerWidth;
    file_panel_width = Math.round(total / 2);
  }

  // Keyboard support for the resizer separator: arrows nudge, Home/End snap.
  function on_resizer_key(e: KeyboardEvent) {
    const step = 16;
    if (e.key === "ArrowRight") {
      file_panel_width = clamp_width(file_panel_width - step);
      e.preventDefault();
    } else if (e.key === "ArrowLeft") {
      file_panel_width = clamp_width(file_panel_width + step);
      e.preventDefault();
    } else if (e.key === "Home") {
      file_panel_width = MIN_PANEL;
    } else if (e.key === "End") {
      const total = main_ref ? main_ref.clientWidth : window.innerWidth;
      file_panel_width = total - MIN_LEFT;
    }
  }

  // Toggle a file's panel: clicking the file already being shown closes the
  // panel; clicking any other file (open or closed) opens it (refreshing
  // the content if it was already open).
  async function toggle_file(path: string) {
    if (open_file === path) {
      open_file = null;
      return;
    }
    open_file = path;
    file_body = "";
    file_error = "";
    file_loading = true;
    try {
      const url = new URL("/fs/read", window.location.href);
      url.searchParams.set("path", path);
      const resp = await fetch(url);
      const data: any = await resp.json().catch(() => null);
      if (!resp.ok || data == null || typeof data.body !== "string") {
        file_error =
          (data && data.error ? data.error : "") + ` (HTTP ${resp.status})`;
      } else {
        file_body = data.body;
      }
    } catch (error) {
      file_error = error as string;
    } finally {
      file_loading = false;
    }
  }

  function close_file() {
    open_file = null;
  }

  // Warn the user before closing/refreshing if a request is still
  // in flight (the NDJSON stream or a pending dialog would be orphaned).
  onMount(() => {
    function handler(e: BeforeUnloadEvent) {
      if (handling_request) {
        e.preventDefault();
        e.returnValue = ""; // required by spec to trigger the native prompt (legacy)
      }
    }
    window.addEventListener("beforeunload", handler);
    // Fire the start request as soon as the page is usable, rather than
    // waiting for the user's first prompt. Fire-and-forget with a catch so a
    // failed /api/start surfaces as a clarion instead of an unhandled rejection.
    check_if_started().catch((error) => {
      session.add_event({ type: "clarion", content: error as string });
    });
    return () => window.removeEventListener("beforeunload", handler);
  });

  async function read_line_by_line(
    response: Response,
    handler: (line: string | null) => void,
  ) {
    const reader = response.body?.getReader();
    if (!reader) return;

    const decoder = new TextDecoder();
    let buffer = "";

    while (true) {
      let { done, value } = await reader.read();
      if (done) {
        // Process any remaining buffer
        if (buffer) handler(buffer);
        handler(null); // null to indicate no more lines
        break;
      }
      buffer += decoder.decode(value, { stream: true });
      let lines = buffer.split("\n");
      buffer = lines.pop() || ""; // Keep the last incomplete line in the buffer
      lines.forEach((line) => handler(line));
    }
  }

  function new_prompt_request(prompt: string): Acp.PromptRequest {
    return {
      sessionId: session.get_id(),
      prompt: [
        {
          type: "text",
          text: prompt,
        },
      ],
    };
  }

  async function handle_response(resp: Response) {
    // Use to track when in think mode while gathering text fragments.
    let text_thinking = false;

    await read_line_by_line(resp, function (line) {
      if (line != null && line.length > 0) {
        let msg = JSON.parse(line);
        switch (msg.type) {
          case "system_info":
            prompt.update_system(msg.host, msg.cwd);
            break;
          case "session_info":
            prompt.update_session(msg.model);
            break;
          case "ask_for_inputs":
            session.ask_for_inputs(
              msg.id,
              msg.title,
              msg.arguments,
              msg.description,
              msg.pre_filled,
            );
            break;
          case "message":
            session.add_event({
              type: `message_${msg.level}`,
              subject: msg.message,
              content: msg.details,
            });
            break;
          case "query":
            switch (msg.content_type) {
              case "text":
                let type =
                  msg.content.startsWith("/") || msg.content.startsWith("!")
                    ? "command"
                    : "query";
                if (msg.via_query_queue) {
                  type = type + "_via_query_queue";
                }
                session.add_event({
                  type: type,
                  content: msg.content,
                });
                break;
              case "image_url":
                session.add_event({
                  type: "query_image_url",
                  content: msg.content,
                });
                break;
              default:
                console.log(`clarion: ${line}`);
                session.add_event({
                  type: "clarion",
                  subject: `Unexpected query: ${line}`,
                });
            }
            break;
          case "llm_text":
            if (msg.reasoning) {
              session.add_event({ type: "llm_think", content: msg.content });
              break;
            }
            // else, check for <think> just in case
            let content = msg.content.trim();
            let think_ix = content.indexOf("</think>");
            // Split think block if present
            if (think_ix > 0) {
              let think = content.substring(0, think_ix + 8).trim();
              if (think.length > 0) {
                session.add_event({ type: "llm_think", content: think });
              }
              content = content.substring(think_ix + 8).trim();
            }
            if (content.length > 0) {
              session.add_event({ type: "llm_text", content: content });
            }
            break;
          case "llm_text_fragment":
            if (msg.reasoning) {
              session.add_event({ type: "llm_think", content: msg.fragment });
              break;
            }
            // else, check for <think> just in case
            let fragment = msg.fragment.trim();
            if (fragment == "<think>") text_thinking = true;
            // if (fragment.length > 0 || msg.fragment.includes("\n")) {
            session.add_event({
              type: text_thinking ? "llm_think" : "llm_text",
              content: msg.fragment,
            });
            // }
            if (fragment == "</think>") text_thinking = false;
            break;
          case "llm_image_url":
            session.add_event({
              type: "llm_image_url",
              content: msg.content,
            });
            break;
          case "llm_tool_call":
            session.add_event({
              type: `tool_call`,
              subject: msg.name,
              content: msg.args,
            });
            break;
          case "security_confirmation":
            session.show_security_confirmation(
              msg.description,
              msg.subjects,
              msg.id,
              msg.banner,
            );
            break;
          case "session_reset":
            session.reset();
            has_content = false;
            break;

          default:
            console.log(`clarion: ${line}`);
            session.add_event({
              type: "clarion",
              content: `Unexpected message: ${line}`,
            });
        }
      }
    });
  }

  // Send start / init request if not already sent
  async function check_if_started() {
    if (!started) {
      started = true;
      let resp = await enkaidu_get_request("start");
      await handle_response(resp);
    }
  }

  // Send drain events request to retrieve any pending events
  async function drain_events_from_enkaidu() {
    let success = true;

    try {
      // likely interrupted connection, so ask Enkaidu to drain remaining events
      // and force a new connection
      let resp = await enkaidu_get_request("drain");
      await handle_response(resp);
    } catch (error) {
      success = false;
    }
    return success;
  }

  // Send query request and return false if exception occurs
  async function ask_enkaidu(query: string) {
    let success = true;
    try {
      query = query.trim();
      session.add_event({
        type:
          query.startsWith("/") || query.startsWith("!") ? "command" : "query",
        content: query,
      });
      has_content = true;
      let resp = await enkaidu_post_request(
        "prompt",
        new_prompt_request(query),
      );
      await handle_response(resp);
    } catch (error) {
      session.add_event({
        type: "clarion",
        content: error as string,
      });
      success = false;
    }
    return success;
  }

  const MAX_TRIES = 3;

  // Handle the user's prompt query request, by sending a query and
  // requesting further events in case of connection error.
  async function on_prompt_ask(query: string) {
    try {
      handling_request = true;
      await check_if_started();

      if (!(await ask_enkaidu(query))) {
        // There was an error, so try and drain events in case Enkaidu
        // is continuing to do work. This
        // re-establises connection with Enkaidu (if possible).
        let tries = 0;
        while (tries < MAX_TRIES) {
          if (await drain_events_from_enkaidu()) break;
          tries += 1;
        }
        if (tries >= MAX_TRIES) {
          // Failed after MAX_TRIES
          session.add_event({
            type: "clarion",
            content: "FAILED to re-connect with Enkaidu.",
          });
        }
      }
    } finally {
      handling_request = false;
      setTimeout(() => {
        prompt.focus();
      }, 10);
    }
  }
</script>

<main>
  <div class="flex h-screen w-full overflow-hidden" bind:this={main_ref}>
    <!-- The transcript column: every level of this chain is a definite
         height (row → drawer → row-tracked grid area → content → column),
         so the Session's internal overflow-scroll is the ONLY scroll here
         and this column can never push the page itself to scroll.
         grid-rows-[100%] locks daisyUI's single auto-sized drawer grid row
         to the full height, which is what makes the h-full chain resolve. -->
    <div
      class="drawer drawer-end grid-rows-[100%] h-full min-w-0 flex-1 overflow-hidden"
    >
      <input id="my-drawer" type="checkbox" class="drawer-toggle" />
      <div class="drawer-content h-full min-h-0 overflow-hidden">
        <div
          class={has_content
            ? "flex h-full flex-col justify-between"
            : "flex h-full flex-col justify-center"}
        >
          <Session
            bind:this={session}
            active_file={open_file}
            on_open_file={toggle_file}
          />
          <Promptbar
            bind:this={prompt}
            onask={on_prompt_ask}
            loading={handling_request}
          />
        </div>
      </div>
      <!-- <Sidebar /> -->
    </div>
    {#if open_file != null}
      <!-- Draggable divide between the transcript column and the file panel:
      a slim flex child whose width the user drags; the transcript's
      flex-1 absorbs the rest, so only the panel's width changes. -->
      <!-- svelte-ignore a11y_no_noninteractive_tabindex -->
      <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
      <div
        role="separator"
        aria-orientation="vertical"
        aria-label="Resize file panel"
        tabindex="0"
        class="resizer h-full"
        style="touch-action:none"
        onpointerdown={start_resize}
        ondblclick={reset_width}
        onkeydown={on_resizer_key}
      ></div>
      <FilePanel
        path={open_file}
        body={file_body}
        loading={file_loading}
        error={file_error}
        onclose={close_file}
        width={file_panel_width}
      />
    {/if}
  </div>
</main>
