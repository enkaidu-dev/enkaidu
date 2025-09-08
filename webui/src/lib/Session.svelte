<script lang="ts">
  import UserCard from "./UserCard.svelte";
  import AsstCard from "./AsstCard.svelte";

  type Event = { type: string; content: string };
  let events: Event[] = $state([]);

  export function add_event(ev: Event) {
    events.push(ev);
  }
</script>

<div class="space-y-3 grid grid-cols-1 w-full p-3">
  {#each events as ev}
    {#if ev.type == "query"}
      <UserCard message={ev.content} />
    {:else if ev.type == "llm"}
      <AsstCard message={ev.content} />
    {/if}
  {/each}
</div>
