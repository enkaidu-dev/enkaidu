<script lang="ts">
  import Markdown from "./Markdown.svelte";
  import ContentUtilities from "./ContentUtilities.svelte";

  // import SvelteMarkdown from "@humanspeak/svelte-markdown";

  let { message }: { message: string } = $props();
</script>

<div
  class="indicator card bg-base-100 text-base-content card-sm shadow-none w-7/8"
  // class="indicator card bg-base-200 text-base-content card-sm shadow-sm w-7/8 place-self-start py-1 dark:border-accent dark:border-1"
>
  <ContentUtilities copy_text={message} />
  <div class="card-body py-1">
    <Markdown content={message} />
  </div>
</div>
