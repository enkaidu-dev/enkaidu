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
  class="indicator card py-1 card-sm shadow-none w-7/8 bg-none border place-self-end {via_query_queue
    ? 'border-info'
    : 'border-accent'}"
>
  <ContentUtilities copy_text={message} />

  <div class="card-body py-1">
    <Markdown
      content={command ? `\`${message}\`` : message}
      add_class="text-gray-600 dark:text-gray-300"
    />
  </div>
</div>
