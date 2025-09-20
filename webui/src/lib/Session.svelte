<script lang="ts">
  import UserCard from "./UserCard.svelte";
  import AsstCard from "./AsstCard.svelte";
  import MsgCard from "./MsgCard.svelte";
  import AsstThinkCard from "./AsstThinkCard.svelte";

  type Event = {
    type: string;
    subject?: string | undefined;
    content?: string | undefined;
  };
  let events: Event[] = $state([]);

  export function add_event(ev: Event) {
    events.push(ev);
  }

  export function get_id() {
    return "not_applicable";
  }
</script>

<div class="mb-auto overflow-scroll">
  <div class="space-y-3 grid grid-cols-1 w-full p-3">
    {#each events as ev}
      {#if ev.type == "query"}
        <UserCard message={ev.content || "??"} />
      {:else if ev.type == "command"}
        <UserCard message={ev.content || "/??"} command />
      {:else if ev.type == "llm"}
        <AsstCard message={ev.content} />
      {:else if ev.type == "think"}
        <AsstThinkCard message={ev.content} />
      {:else if ev.type.startsWith("message_")}
        <MsgCard
          message={ev.subject}
          level={ev.type.split("_").at(-1) || "info"}
          details={ev.content}
        />
      {/if}
    {/each}
  </div>
</div>
