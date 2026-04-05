<script lang="ts">
  import Markdown from "./Markdown.svelte";
  import ContentUtilities from "./ContentUtilities.svelte";

  let {
    message,
    command,
    via_query_queue,
  }: {
    message: string;
    command?: boolean;
    via_query_queue?: boolean;
  } = $props();
</script>

<div
  class="card py-1 card-sm shadow-sm w-7/8 place-self-end {via_query_queue
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
