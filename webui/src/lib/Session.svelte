<script lang="ts">
  import { enkaidu_post_request } from "../utilities";
  import * as Common from "../common_types";

  import MsgCard from "./MsgCard.svelte";
  import AsstTextCard from "./AsstTextCard.svelte";
  import AsstImageCard from "./AsstImageCard.svelte";
  import AsstThinkCard from "./AsstThinkCard.svelte";
  import SecurityConfirmDialog from "./SecurityConfirmDialog.svelte";
  import UserTextCard from "./UserTextCard.svelte";
  import UserImageCard from "./UserImageCard.svelte";
  import ClarionCard from "./ClarionCard.svelte";
  import InputsDialog from "./InputsDialog.svelte";
  import ToolCallCard from "./ToolCallCard.svelte";

  // Tolerance band (px) for "close enough to the bottom" so sub-pixel /
  // rounded scroll values don't flip the flag spuriously.
  const SCROLL_TOLERANCE = 50;

  const scrollToBottom = (node: HTMLElement, _list: Event[]) => {
    // Assume the user starts at the bottom on a fresh session. The flag is
    // ONLY updated by real scroll events (never by content growth), so the
    // "new content pushed me off the bottom" edge case in the plan cannot
    // falsely suppress the next auto-scroll: a user who was at the bottom
    // keeps the flag true until they actually scroll.
    let at_bottom = true;

    const isAtBottom = () =>
      node.scrollTop + node.clientHeight >=
      node.scrollHeight - SCROLL_TOLERANCE;

    const handleScroll = () => {
      at_bottom = isAtBottom();
    };

    const maybeScroll = () => {
      // Only auto-scroll to the bottom when the user is already there.
      // Suppress the scroll while they have scrolled up; once they return
      // to the bottom edge the flag flips back and auto-scroll resumes.
      if (!at_bottom) return;
      node.scroll({ top: node.scrollHeight, behavior: "smooth" });
    };

    node.addEventListener("scroll", handleScroll);
    maybeScroll();

    return {
      update: maybeScroll,
      destroy: () => node.removeEventListener("scroll", handleScroll),
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
  };

  let entries: SessionEntry[] = $state([]);

  let security_confirm_dialog_config: Common.SecurityConfirmDialogConfig =
    $state({
      show: false,
      description: "",
      subject: "",
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
  }

  export function add_event(ev: Event) {
    let last = entries.at(-1);
    let ev_data = { subject: ev.subject, content: ev.content };
    if (last && last.type == ev.type) {
      if (last.type == "llm_text" || last.type == "llm_think") {
        // append text if it's LLM or THINK text
        // this allows us to show streaming text
        let content = (last.data[0].content || "") + ev_data.content;
        last.data[0].content = content;
      } else {
        // append to data[] otherwise
        last.data.push(ev_data);
      }
    } else {
      check_and_trim_last_entry();
      // Append the new event type
      entries.push({
        type: ev.type,
        data: [ev_data],
      });
    }
  }

  export function get_id() {
    return "not_applicable";
  }

  export function show_security_confirmation(
    description: string,
    subject: string,
    id: string,
  ) {
    security_confirm_dialog_config.show = true;
    security_confirm_dialog_config.description = description;
    security_confirm_dialog_config.subject = subject;
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

<div use:scrollToBottom={entries} class="mb-auto overflow-scroll">
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
      {#each entries as entry}
        {#if entry.type == "query"}
          <UserTextCard message={entry.data[0].content || "??"} />
        {:else if entry.type == "command"}
          <UserTextCard message={entry.data[0].content || "/??"} command />
        {:else if entry.type == "query_via_query_queue"}
          <UserTextCard
            message={entry.data[0].content || "??"}
            via_query_queue
          />
        {:else if entry.type == "command_via_query_queue"}
          <UserTextCard
            message={entry.data[0].content || "/??"}
            command
            via_query_queue
          />
        {:else if entry.type == "query_image_url"}
          <UserImageCard image_url={entry.data[0].content || "??"} />
        {:else if entry.type == "llm_text"}
          <AsstTextCard message={entry.data[0].content || "??"} />
        {:else if entry.type == "llm_think"}
          <AsstThinkCard message={entry.data[0].content} />
        {:else if entry.type == "llm_image_url"}
          <AsstImageCard image_url={entry.data[0].content || "??"} />
        {:else if entry.type == "clarion"}
          <ClarionCard subject={entry.data[0].content || "???"} />
        {:else if entry.type == "tool_call"}
          <ToolCallCard
            name={entry.data[0].subject as string}
            args={entry.data[0].content as string}
          />
        {:else if entry.type.startsWith("message_")}
          <MsgCard
            level={entry.type.split("_").at(-1) || "info"}
            data={entry.data}
          />
        {/if}
      {/each}
    {/if}
  </div>
</div>

<SecurityConfirmDialog
  subject={security_confirm_dialog_config.subject}
  description={security_confirm_dialog_config.description}
  id={security_confirm_dialog_config.id}
  show={security_confirm_dialog_config.show}
  onconfirm={handle_security_confirmation}
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
