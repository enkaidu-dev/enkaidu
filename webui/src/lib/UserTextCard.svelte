<script lang="ts">
  import Markdown from "./Markdown.svelte";
  import ContentUtilities from "./ContentUtilities.svelte";

  let { message, command }: { message: string; command?: boolean } = $props();
</script>

<div class="card bg-accent py-1 card-sm shadow-sm w-7/8 place-self-end">
  <ContentUtilities copy_text={message} />

  <div class="card-body py-1">
    <Markdown
      content={command ? `\`${message}\`` : message}
      add_class="text-accent-content"
    />
  </div>
</div>
