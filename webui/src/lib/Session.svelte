<script lang="ts">
  import UserCard from "./UserCard.svelte";
  import AsstCard from "./AsstCard.svelte";
  import MsgCard from "./MsgCard.svelte";
  import AsstThinkCard from "./AsstThinkCard.svelte";

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

  function check_and_trim_last_entry() {
    let last = entries.at(-1);
    if (last) {
      // Check if last one is text and if it has any text in it
      if (last.type == "llm" || last.type == "think") {
        let content = last.data[0].content?.trim();
        if (content && content.length == 0) {
          // The previous one has empty text, so just drop it.
          entries.pop();
        }
      }
    }
  }

  export function add_event(ev: Event) {
    let last = entries.at(-1);
    let ev_data = { subject: ev.subject, content: ev.content };
    if (last && last.type == ev.type) {
      if (last.type == "llm" || last.type == "think") {
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
</script>

<div use:scrollToBottom={entries} class="mb-auto overflow-scroll">
  <div class="space-y-3 grid grid-cols-1 w-full max-w-5xl p-3 mx-auto">
    {#each entries as entry}
      {#if entry.type == "query"}
        <UserCard message={entry.data[0].content || "??"} />
      {:else if entry.type == "command"}
        <UserCard message={entry.data[0].content || "/??"} command />
      {:else if entry.type == "llm"}
        <AsstCard message={entry.data[0].content} />
      {:else if entry.type == "think"}
        <AsstThinkCard message={entry.data[0].content} />
      {:else if entry.type.startsWith("message_")}
        <MsgCard
          level={entry.type.split("_").at(-1) || "info"}
          data={entry.data}
        />
      {/if}
    {/each}
  </div>
</div>
