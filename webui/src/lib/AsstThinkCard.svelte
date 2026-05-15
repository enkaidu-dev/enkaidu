<script lang="ts">
  import Markdown from "./Markdown.svelte";
  // import SvelteMarkdown from "@humanspeak/svelte-markdown";

  let { message } = $props();
</script>

<div
  class="card bg-base-200 text-base-content italic card-xs shadow-sm w-7/8 place-self-start dark:border-accent dark:border-1"
>
  <div class="collapse collapse-arrow py-0">
    <input type="checkbox" />
    <div class="collapse-title card-title py-0 text-ghost text-xs">
      Thinking
    </div>
    <div class="collapse-content text-base text-sm">
      <Markdown content={message} add_class="text-sm" />
    </div>
  </div>
</div>
