<script lang="ts">
  import SvelteMarkdown from "@humanspeak/svelte-markdown";

  let { message } = $props();
</script>

<div
  class="card bg-primary-content text-primary card-sm shadow-sm w-7/8 place-self-start py-1"
>
  <div class="card-body text-base py-1">
    <h2 class="card-title text-sm">Assistant</h2>
    <SvelteMarkdown source={message} />
  </div>
</div>
