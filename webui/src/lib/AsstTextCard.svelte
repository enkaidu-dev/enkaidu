<script lang="ts">
  import Markdown from "./Markdown.svelte";
  // import SvelteMarkdown from "@humanspeak/svelte-markdown";

  let { message }: { message: string } = $props();
</script>

<div
  class="card bg-base-300 text-base-content card-sm shadow-sm w-7/8 place-self-start py-1 dark:border-accent dark:border-1"
>
  <div class="card-body py-1">
    <h2 class="card-title text-sm text-accent">Assistant</h2>
    <Markdown content={message} />
  </div>
</div>
