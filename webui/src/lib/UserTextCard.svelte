<script lang="ts">
  import Markdown from "./Markdown.svelte";
  import ContentUtilities from "./ContentUtilities.svelte";

  let {
    message,
    command,
    via_macro,
  }: {
    message: string;
    command?: boolean;
    via_macro?: boolean;
  } = $props();
</script>

<div
  class="card py-1 card-sm shadow-sm w-7/8 place-self-end {via_macro
    ? 'bg-info'
    : 'bg-accent'}"
>
  <ContentUtilities copy_text={message} />

  <div class="card-body py-1">
    <Markdown
      content={command ? `\`${message}\`` : message}
      add_class="text-accent-content"
    />
  </div>
</div>
