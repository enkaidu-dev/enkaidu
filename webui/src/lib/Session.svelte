<script lang="ts">
  import { enkaidu_post_request } from "../utilities";
  import * as Common from "../common_types";

  import MsgCard from "./MsgCard.svelte";
  import AsstTextCard from "./AsstTextCard.svelte";
  import AsstImageCard from "./AsstImageCard.svelte";
  import AsstThinkCard from "./AsstThinkCard.svelte";
  import SecurityConfirmDialog from "./SecurityConfirmDialog.svelte";
  import SecurityPermissionDialog from "./SecurityPermissionDialog.svelte";
  import UserTextCard from "./UserTextCard.svelte";
  import UserImageCard from "./UserImageCard.svelte";
  import ClarionCard from "./ClarionCard.svelte";
  import InputsDialog from "./InputsDialog.svelte";
  import ToolCallCard from "./ToolCallCard.svelte";
  import HelpCard from "./HelpCard.svelte";
  import ActivityGroup from "./ActivityGroup.svelte";

  // Tolerance band (px) for "close enough to the bottom."  A generous value
  // so sub-pixel rounding and brief layout transients (group form / collapse)
  // don't spuriously break the pin.
  const SCROLL_TOLERANCE = 80;

  // The user's *own* submissions: a prompt, a slash/! command, an image, or
  // any of those surfaced from the query queue. Each lands at the tail of the
  // transcript as a new entry. When one becomes the tail, we force a scroll to
  // the bottom and re-pin the follow, so the user's new message and its
  // response come into view even after the transcript was scrolled up to read
  // history. (Ordinary streaming appends an llm_text/llm_think tail instead,
  // which must NOT re-pin — that is the "read at your own pace" behavior, so a
  // scrolled-up transcript keeps its place while old output keeps streaming.)
  const USER_PROMPT_TYPES = new Set([
    "query",
    "command",
    "query_via_query_queue",
    "command_via_query_queue",
    "query_image_url",
  ]);

  const scrollToBottom = (node: HTMLElement, _list: Event[]) => {
    // `stuck` tracks whether the user is "pinned to the bottom."
    // Starts true (a fresh session starts at the bottom). Only a
    // user-initiated scroll away from the bottom breaks the pin;
    // scrolling back down (including our own programmatic scroll)
    // re-pins.
    let stuck = true;

    const isAtBottom = () =>
      node.scrollTop + node.clientHeight >=
      node.scrollHeight - SCROLL_TOLERANCE;

    // On any scroll event (user or programmatic) update the sticky flag.
    // A scroll to near-bottom sets stuck = true; a scroll up away
    // from the bottom sets it false.
    const handleScroll = () => {
      stuck = isAtBottom();
    };

    // Coalesce rapid `update` calls (streaming fragments, group churn)
    // into a single rAF per frame so we scroll at most once per paint,
    // after the browser has reflowed the new DOM.
    let rafId = 0;

    const maybeScroll = () => {
      // A newly submitted prompt re-engages the bottom pin: even if the user
      // scrolled up to read earlier output, their own new message is a reason
      // to follow the conversation downward again.
      const last = entries.at(-1);
      if (last && USER_PROMPT_TYPES.has(last.type)) stuck = true;

      if (!stuck) return;
      cancelAnimationFrame(rafId);
      rafId = requestAnimationFrame(() => {
        // Re-check both conditions inside the frame: the user may have
        // scrolled up between the update and the paint, or layout may
        // have shifted so we are already at the bottom.
        if (stuck && !isAtBottom()) {
          node.scrollTop = node.scrollHeight;
        }
      });
    };

    node.addEventListener("scroll", handleScroll, { passive: true });
    maybeScroll();

    return {
      update: maybeScroll,
      destroy: () => {
        cancelAnimationFrame(rafId);
        node.removeEventListener("scroll", handleScroll);
      },
    };
  };

  type Event = {
    type: string;
    subject?: string | undefined;
    content?: string | undefined;
  };

  type SessionData = {
    subject?: string | undefined;
    content?: string | undefined;
  };

  type SessionEntry = {
    type: string;
    data: SessionData[];
    // File paths (referenced by file-writing tool calls) that this
    // assistant text entry should offer as viewable files.
    files?: string[];
  };

  let entries: SessionEntry[] = $state([]);

  // File paths extracted from file-modifying tool calls that are waiting to
  // be attached to the *next* assistant text entry (whose card renders the
  // file buttons).
  let pending_files: string[] = $state([]);

  const FILE_TOOLS = new Set(["str_replace_in_text_file", "write_text_file"]);

  let {
    active_file = null,
    on_open_file,
  }: {
    active_file?: string | null;
    on_open_file?: (path: string) => void;
  } = $props();

  // ---- Activity grouping ---------------------------------------------------
  // Consecutive "agent working" entries (think blocks, tool calls, messages)
  // are collapsed into a single ActivityGroup to keep long runs compact.
  // User queries, assistant text, alerts, and images stay standalone.
  const GROUPABLE = new Set(["llm_think", "tool_call"]);

  function is_groupable(entry: SessionEntry): boolean {
    if (GROUPABLE.has(entry.type)) return true;
    return entry.type.startsWith("message_");
  }

  type GroupedEntry =
    | { kind: "group"; items: SessionEntry[]; active: boolean }
    | { kind: "standalone"; entry: SessionEntry };

  let grouped: GroupedEntry[] = $derived.by(() => {
    const result: GroupedEntry[] = [];
    let current: SessionEntry[] = [];

    const flush = (active: boolean) => {
      if (current.length === 0) return;
      if (current.length === 1) {
        // Single item: no grouping chrome, render as a standalone card.
        result.push({ kind: "standalone", entry: current[0] });
      } else {
        result.push({ kind: "group", items: current, active });
      }
      current = [];
    };

    for (const entry of entries) {
      if (is_groupable(entry)) {
        current.push(entry);
      } else {
        flush(false);
        result.push({ kind: "standalone", entry });
      }
    }

    // Flush trailing group — active if the last entry is still groupable
    // (i.e. the agent is mid-run and no response has arrived yet).
    const lastEntry = entries.at(-1);
    const lastActive = lastEntry ? is_groupable(lastEntry) : false;
    flush(lastActive);

    return result;
  });

  let security_permission_dialog_config: Common.SecurityPermissionDialogConfig =
    $state({
      show: false,
      description: "",
      subjects: [],
      banner: null,
      id: "",
    });

  let security_confirm_dialog_config: Common.SecurityConfirmDialogConfig =
    $state({
      show: false,
      description: "",
      subjects: [],
      banner: null,
      id: "",
    });

  let inputs_dialog: InputsDialog;

  let inputs_dialog_config: Common.InputDialogConfig = $state({
    show: false,
    id: "",
    title: "",
    description: "",
    input_arguments: [],
  });

  function check_and_trim_last_entry() {
    let last = entries.at(-1);
    if (last) {
      // Check if last one is text and if it has any text in it
      if (last.type == "llm_text" || last.type == "llm_think") {
        let content = last.data[0].content?.trim();
        if (typeof content == "string" && content.length == 0) {
          // The previous one has empty text, so just drop it.
          entries.pop();
        }
      }
    }
  }

  export function reset() {
    entries.length = 0;
    pending_files.length = 0;
  }

  export function add_event(ev: Event) {
    // Harvest the file_path from file-modifying tool calls; it rides onto
    // the next assistant text entry as a clickable file button.
    if (
      ev.type === "tool_call" &&
      typeof ev.subject === "string" &&
      FILE_TOOLS.has(ev.subject) &&
      typeof ev.content === "string"
    ) {
      try {
        const path: unknown = JSON.parse(ev.content)?.file_path;
        if (
          typeof path === "string" &&
          path.length > 0 &&
          !pending_files.includes(path)
        ) {
          pending_files.push(path);
        }
      } catch {
        // args weren't valid JSON — nothing to harvest
      }
    }

    let last = entries.at(-1);
    let ev_data = { subject: ev.subject, content: ev.content };
    // Streaming LLM/think text coalesces into the last entry's single
    // record; other same-type events append to its data[] (e.g.
    // message_* — MsgCard renders every record). Consecutive tool_call
    // events deliberately do NOT coalesce: each call is its own
    // transcript step (grouping, "N steps", and the group title all
    // count entries), and the tool-call cards show only data[0] —
    // merging a run of calls into one entry would hide every call
    // after the first.
    let coalesced = false;
    if (last && last.type == ev.type) {
      if (last.type == "llm_text" || last.type == "llm_think") {
        // append text if it's LLM or THINK text
        // this allows us to show streaming text
        let content = (last.data[0].content || "") + ev_data.content;
        last.data[0].content = content;
        coalesced = true;
      } else if (ev.type != "tool_call") {
        // append to data[] otherwise
        last.data.push(ev_data);
        coalesced = true;
      }
    }
    if (!coalesced) {
      check_and_trim_last_entry();
      // Append the new event type
      const entry: SessionEntry = { type: ev.type, data: [ev_data] };
      // Attach any harvested file paths to this assistant text entry.
      if (ev.type === "llm_text" && pending_files.length > 0) {
        // splice takes the items AND empties the pending list in one move;
        // assigning the pending array directly (then clearing it) would
        // leave the entry holding an empty array.
        entry.files = pending_files.splice(0);
      }
      entries.push(entry);
    }
  }

  export function get_id() {
    return "not_applicable";
  }

  export function show_security_confirmation(
    description: string,
    subjects: string[],
    id: string,
    banner: Common.SecurityBanner | null,
  ) {
    security_confirm_dialog_config.show = true;
    security_confirm_dialog_config.description = description;
    security_confirm_dialog_config.subjects = subjects;
    security_confirm_dialog_config.banner = banner;
    security_confirm_dialog_config.id = id;
  }

  async function send_confirmation_response(id: string, approved: boolean) {
    try {
      await enkaidu_post_request("confirmation", { id, approved });
    } catch (error) {
      console.error("Failed to send confirmation response:", error);
    }
  }

  function handle_security_confirmation(id: string, approved: boolean) {
    security_confirm_dialog_config.show = false;
    send_confirmation_response(id, approved);
  }

  export function show_security_permission(
    description: string,
    subjects: string[],
    id: string,
    banner: Common.SecurityBanner | null,
  ) {
    security_permission_dialog_config.show = true;
    security_permission_dialog_config.description = description;
    security_permission_dialog_config.subjects = subjects;
    security_permission_dialog_config.banner = banner;
    security_permission_dialog_config.id = id;
  }

  async function send_permission_response(
    id: string,
    approved: boolean,
    remember: boolean,
  ) {
    try {
      await enkaidu_post_request("permission", { id, approved, remember });
    } catch (error) {
      console.error("Failed to send permission response:", error);
    }
  }

  function handle_security_permission(
    id: string,
    approved: boolean,
    remember: boolean,
  ) {
    security_permission_dialog_config.show = false;
    send_permission_response(id, approved, remember);
  }

  export function ask_for_inputs(
    id: string,
    title: string,
    input_args: Common.InputArg[],
    description: string | undefined,
    pre_filled: Common.InputValues | null,
  ) {
    inputs_dialog_config.id = id;
    inputs_dialog_config.title = title;
    inputs_dialog_config.description = description;
    inputs_dialog_config.input_arguments = input_args;
    inputs_dialog_config.pre_filled = pre_filled;
    inputs_dialog.open();
  }

  async function send_inputs_response(id: string, inputs: Common.InputValues) {
    try {
      await enkaidu_post_request("inputs", { id, inputs });
    } catch (error) {
      console.error("Failed to send inputs response:", error);
    }
  }

  function handle_inputs_submission(id: string, inputs: Common.InputValues) {
    inputs_dialog_config.show = false;
    send_inputs_response(id, inputs);
  }
</script>

<div
  use:scrollToBottom={entries}
  class="mb-auto flex-1 min-h-0 overflow-scroll"
>
  <div class="space-y-6 flex flex-col w-full max-w-3xl p-3 mx-auto">
    {#if entries.length === 0}
      <div
        class="flex-1 flex flex-col items-center justify-center min-h-[50vh]"
      >
        <p class="text-base-content/40 text-xl font-medium my-3">
          <img src="/favicon.png" alt="Enkaidu" />
        </p>
        <p class="text-base-content/40 text-3xl font-medium my-3">
          How can I help you?
        </p>
      </div>
    {:else}
      {#each grouped as g, gi (gi)}
        {#if g.kind == "group"}
          <ActivityGroup items={g.items} active={g.active} />
        {:else if g.entry.type == "query"}
          <UserTextCard message={g.entry.data[0].content || "??"} />
        {:else if g.entry.type == "command"}
          <UserTextCard message={g.entry.data[0].content || "/??"} command />
        {:else if g.entry.type == "query_via_query_queue"}
          <UserTextCard
            message={g.entry.data[0].content || "??"}
            via_query_queue
          />
        {:else if g.entry.type == "command_via_query_queue"}
          <UserTextCard
            message={g.entry.data[0].content || "/??"}
            command
            via_query_queue
          />
        {:else if g.entry.type == "query_image_url"}
          <UserImageCard image_url={g.entry.data[0].content || "??"} />
        {:else if g.entry.type == "llm_text"}
          <AsstTextCard
            message={g.entry.data[0].content || "??"}
            files={g.entry.files}
            {active_file}
            {on_open_file}
          />
        {:else if g.entry.type == "llm_think"}
          <AsstThinkCard
            message={g.entry.data[0].content || "??"}
            active={g.entry === entries.at(-1)}
          />
        {:else if g.entry.type == "llm_image_url"}
          <AsstImageCard image_url={g.entry.data[0].content || "??"} />
        {:else if g.entry.type == "clarion"}
          <ClarionCard subject={g.entry.data[0].content || "???"} />
        {:else if g.entry.type == "tool_call"}
          <!-- One card per record: add_event keeps each tool call in its
               own entry, but render every record so a coalesced entry can
               never silently hide a call. -->
          {#each g.entry.data as d, di (di)}
            <ToolCallCard
              name={d.subject as string}
              args={d.content as string}
            />
          {/each}
        {:else if g.entry.type == "help_response"}
          <HelpCard
            title={g.entry.data[0].subject || "Help"}
            body={g.entry.data[0].content || ""}
            active={g.entry === entries.at(-1)}
          />
        {:else if g.entry.type.startsWith("message_")}
          <MsgCard
            level={g.entry.type.split("_").at(-1) || "info"}
            data={g.entry.data}
          />
        {/if}
      {/each}
    {/if}
  </div>
</div>

<SecurityConfirmDialog
  subjects={security_confirm_dialog_config.subjects}
  banner={security_confirm_dialog_config.banner}
  description={security_confirm_dialog_config.description}
  id={security_confirm_dialog_config.id}
  show={security_confirm_dialog_config.show}
  onconfirm={handle_security_confirmation}
/>

<SecurityPermissionDialog
  subjects={security_permission_dialog_config.subjects}
  banner={security_permission_dialog_config.banner}
  description={security_permission_dialog_config.description}
  id={security_permission_dialog_config.id}
  show={security_permission_dialog_config.show}
  onconfirm={handle_security_permission}
/>

<InputsDialog
  bind:this={inputs_dialog}
  id={inputs_dialog_config.id}
  title={inputs_dialog_config.title}
  description={inputs_dialog_config.description}
  input_arguments={inputs_dialog_config.input_arguments}
  pre_filled={inputs_dialog_config.pre_filled}
  show={inputs_dialog_config.show}
  onsubmit={handle_inputs_submission}
/>
