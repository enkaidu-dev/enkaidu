<script lang="ts">
  import Markdown from "./Markdown.svelte";
  import ContentUtilities from "./ContentUtilities.svelte";
  import type { UtilityAction } from "./ContentUtilities.svelte";
  import Copy from "virtual:icons/pixelarticons/copy";
  import CheckDouble from "virtual:icons/pixelarticons/check-double";

  let { message }: { message: string } = $props();

  // Assistant-message actions. For now just Copy (copies the raw markdown);
  // future assistant-only actions (regenerate, thumbs up/down, quote, ...)
  // are added as additional entries here.
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

<div class="group relative w-7/8 bg-base-100 text-base-content">
  <div class="py-1">
    <Markdown content={message} />
  </div>
  <ContentUtilities actions={actions} />
</div>
