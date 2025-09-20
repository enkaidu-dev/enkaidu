<script lang="ts">
  import Markdown from "./Markdown.svelte";

  let { message, command }: { message: string; command?: boolean } = $props();
</script>

<div class="card bg-primary card-sm shadow-sm w-7/8 place-self-end">
  <div class="card-body py-1">
    <Markdown content={message} add_class="text-primary-content" />
  </div>
</div>
