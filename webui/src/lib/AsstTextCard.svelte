<script lang="ts">
  import Markdown from "./Markdown.svelte";
  import ContentUtilities from "./ContentUtilities.svelte";
  import type { UtilityAction } from "./ContentUtilities.svelte";
  import Copy from "virtual:icons/pixelarticons/copy";
  import CheckDouble from "virtual:icons/pixelarticons/check-double";

  let {
    message,
    files = [] as string[],
    active_file = null,
    on_open_file,
  }: {
    message: string;
    // File paths to offer as buttons (from file-modifying tool calls);
    // rendered as a rows-of-two grid above the card content.
    files?: string[];
    // The path currently shown in the file side panel (toggled state).
    active_file?: string | null;
    on_open_file?: (path: string) => void;
  } = $props();

  function file_name(path: string) {
    const parts = path.split("/").filter(Boolean);
    return parts.length > 0 ? parts[parts.length - 1] : path;
  }

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
  {#if files.length > 0}
    <!-- Aligned with the response text (no horizontal padding, matching
         the .py-1 content div below); responsive: 1 / 2 / 3 columns as the
         window grows. -->
    <div
      class="grid grid-cols-1 gap-2 pt-1 sm:grid-cols-2 lg:grid-cols-3"
    >
      {#each files as path (path)}
        <button
          type="button"
          class="file-chip"
          class:active={active_file === path}
          title={path}
          aria-label={path}
          onclick={() => on_open_file?.(path)}
        >
          {file_name(path)}
        </button>
      {/each}
    </div>
  {/if}
  <div class="py-1">
    <Markdown content={message} />
  </div>
  <ContentUtilities {actions} />
</div>
