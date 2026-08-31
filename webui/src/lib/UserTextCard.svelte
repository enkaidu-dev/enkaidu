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
  class="group indicator w-7/8 place-self-end py-1 rounded-2xl text-base-content/80 {via_query_queue
      ? 'bg-info/10'
      : 'bg-base-300'}"
>
  <ContentUtilities copy_text={message} />

  <div class="px-3 py-2">
    <Markdown
      content={command ? `\`${message}\`` : message}
      add_class="text-gray-600 dark:text-gray-300"
    />
  </div>
</div>
