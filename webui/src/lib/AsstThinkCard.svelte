<script lang="ts">
  import SvelteMarkdown from "@humanspeak/svelte-markdown";

  let { message } = $props();
</script>

<div
  class="card bg-primary-content text-primary py-1 italic card-sm shadow-sm w-7/8 place-self-start"
>
  <div class="collapse collapse-arrow py-1">
    <input type="checkbox" />
    <div class="collapse-title card-title text-sm">Assistant &lt;THINK&gt;</div>
    <div class="collapse-content text-base">
      <SvelteMarkdown source={message} />
    </div>
  </div>
</div>
