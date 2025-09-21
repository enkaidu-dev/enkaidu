<script lang="ts">
  import Markdown from "./Markdown.svelte";
  // import SvelteMarkdown from "@humanspeak/svelte-markdown";

  let { message } = $props();
</script>

<div
  class="card bg-base-300 text-base-content py-1 italic card-sm shadow-sm w-7/8 place-self-start dark:border-accent dark:border-1"
>
  <div class="collapse collapse-arrow py-1">
    <input type="checkbox" />
    <div class="collapse-title card-title text-accent text-sm">
      Assistant &lt;THINK&gt;
    </div>
    <div class="collapse-content text-base">
      <Markdown content={message} />
    </div>
  </div>
</div>
