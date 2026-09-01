<script lang="ts">
  import Markdown from "./Markdown.svelte";
  import ContentUtilities from "./ContentUtilities.svelte";
  import type { UtilityAction } from "./ContentUtilities.svelte";
  import Copy from "virtual:icons/pixelarticons/copy";
  import CheckDouble from "virtual:icons/pixelarticons/check-double";

  let {
    message,
    command,
    via_query_queue,
  }: {
    message: string;
    command?: boolean;
    via_query_queue?: boolean;
  } = $props();

  // User-message actions (intentionally a separate list from the assistant
  // card — the two content types can carry different actions).
  const actions: UtilityAction[] = [
    {
      id: "copy",
      label: "Copy",
      icon: Copy,
      success_icon: CheckDouble,
      success_label: "Done",
      onAction: () => navigator.clipboard.writeText(message),
    },
  ];
</script>

<div
  class="group w-7/8 place-self-end py-1 rounded-2xl text-base-content/80 {via_query_queue
      ? 'bg-info/10'
      : 'bg-base-300'}"
>
  <div class="px-3 py-2">
    <Markdown
      content={command ? `\`${message}\`` : message}
      add_class="text-gray-600 dark:text-gray-300"
    />
  </div>
  <div class="px-3">
    <ContentUtilities actions={actions} />
  </div>
</div>
