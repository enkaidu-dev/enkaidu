<script lang="ts">
  import Markdown from "./Markdown.svelte";

  let { message } = $props();
</script>

<div class="w-7/8 place-self-start text-base-content/50">
   <details class="group/think">
      <summary
       class="cursor-pointer list-none py-0 text-xs font-medium text-base-content/40 hover:text-base-content/60 transition-colors select-none flex items-center gap-1"
      >
       <span class="text-base-content/30 group-open/think:rotate-90 transition-transform text-[0.85em] leading-none">▶</span>
       Thinking
      </summary>
      <div class="text-base-content/60 ms-5 ps-2 mt-1 max-h-40 overflow-y-scroll">
        <Markdown content={message} add_class="text-sm" />
      </div>
   </details>
</div>
