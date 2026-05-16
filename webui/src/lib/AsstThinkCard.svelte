<script lang="ts">
  import Markdown from "./Markdown.svelte";
  // import SvelteMarkdown from "@humanspeak/svelte-markdown";

  let { message } = $props();
</script>

<div
  class="card bg-none mb-0 text-base-content italic card-xs shadow-none w-7/8 place-self-start"
  // class="card bg-base-200 text-base-content italic card-xs shadow-sm w-7/8 place-self-start dark:border-accent dark:border"
>
  <div class="collapse collapse-arrow py-0">
    <input type="checkbox" />
    <div
      class="collapse-title card-title py-0 text-ghost text-xs after:inset-s-5 after:inset-e-auto pe-4 ps-10"
    >
      Thinking
    </div>
    <div
      class="collapse-content text-base ms-6 ps-2 border-l-2 border-l-gray-400"
    >
      <Markdown content={message} add_class="text-sm" />
    </div>
  </div>
</div>
