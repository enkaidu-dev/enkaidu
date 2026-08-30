<script lang="ts">
  import Markdown from "./Markdown.svelte";
  import ContentUtilities from "./ContentUtilities.svelte";

  let { message }: { message: string } = $props();
</script>

<div class="indicator w-7/8 bg-base-100 text-base-content">
  <ContentUtilities copy_text={message} />
  <div class="py-1">
    <Markdown content={message} />
  </div>
</div>
