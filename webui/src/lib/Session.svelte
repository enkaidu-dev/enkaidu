<script lang="ts">
  import { enkaidu_post_request } from "../utilities";

  import MsgCard from "./MsgCard.svelte";
  import AsstTextCard from "./AsstTextCard.svelte";
  import AsstImageCard from "./AsstImageCard.svelte";
  import AsstThinkCard from "./AsstThinkCard.svelte";
  import ShellConfirmDialog from "./ShellConfirmDialog.svelte";
  import UserTextCard from "./UserTextCard.svelte";
  import UserImageCard from "./UserImageCard.svelte";
  import ClarionCard from "./ClarionCard.svelte";

  const scrollToBottom = (node: HTMLElement, _list: Event[]) => {
    const scroll = () =>
      node.scroll({
        top: node.scrollHeight,
        behavior: "smooth",
      });
    scroll();

    return { update: scroll };
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
  let shell_confirm_dialog = $state({
    show: false,
    command: "",
    id: "",
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

  export function show_confirmation(command: string, id: string) {
    shell_confirm_dialog.show = true;
    shell_confirm_dialog.command = command;
    shell_confirm_dialog.id = id;
  }

  async function send_confirmation_response(id: string, approved: boolean) {
    try {
      await enkaidu_post_request("confirmation", { id, approved });
    } catch (error) {
      console.error("Failed to send confirmation response:", error);
    }
  }

  function handle_shell_confirmation(id: string, approved: boolean) {
    shell_confirm_dialog.show = false;
    send_confirmation_response(id, approved);
  }
</script>

<div use:scrollToBottom={entries} class="mb-auto overflow-scroll">
  <div class="space-y-3 grid grid-cols-1 w-full max-w-5xl p-3 mx-auto">
    {#each entries as entry}
      {#if entry.type == "query"}
        <UserTextCard message={entry.data[0].content || "??"} />
      {:else if entry.type == "command"}
        <UserTextCard message={entry.data[0].content || "/??"} command />
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
      {:else if entry.type.startsWith("message_")}
        <MsgCard
          level={entry.type.split("_").at(-1) || "info"}
          data={entry.data}
        />
      {/if}
    {/each}
  </div>
</div>

<ShellConfirmDialog
  command={shell_confirm_dialog.command}
  id={shell_confirm_dialog.id}
  show={shell_confirm_dialog.show}
  onconfirm={handle_shell_confirmation}
/>
