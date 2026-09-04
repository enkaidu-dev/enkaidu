<script lang="ts">
  import type { Snippet } from "svelte";

  let {
    language,
    source,
    rendered = true,
    failed = false,
    error = "",
    view = $bindable("diagram"),
    diagramLabel = "Diagram",
    codeLabel = "Source",
    children,
  }: {
    language: string;
    source: string;
    rendered?: boolean;
    failed?: boolean;
    error?: string;
    view?: "diagram" | "code";
    diagramLabel?: string;
    codeLabel?: string;
    children?: Snippet;
  } = $props();
</script>

<div class="not-prose my-6 w-full overflow-hidden rounded-lg border border-base/85 text-sm">
  <div class="flex items-center justify-between gap-2 border-b border-base/85 bg-base-200 px-3 py-1.5">
    <span class="font-mono text-xs text-base-content/50">{language}</span>
    <div class="flex items-center gap-1">
      {#if rendered}
        {#if !failed}
          <button
            type="button"
            class="action-chip"
            class:active={view === "diagram"}
            aria-pressed={view === "diagram"}
            onclick={() => (view = "diagram")}>{diagramLabel}</button>
        {/if}
        <button
          type="button"
          class="action-chip"
          class:active={view === "code"}
          aria-pressed={view === "code"}
          onclick={() => (view = "code")}>{codeLabel}</button>
      {/if}
    </div>
  </div>

  {#if failed && view === "code"}
    <div class="border-b border-base/85 bg-error/10 px-3 py-1.5 text-xs text-error/90">
      Couldn't render diagram: {error}
    </div>
  {/if}

  {#if view === "diagram" && rendered && !failed}
    {@render children?.()}
  {:else if view === "code" && source}
    <div class="enkaidu-code group/code relative">
      <button
        type="button"
        data-copy-code
        aria-label="Copy code"
        class="enkaidu-copy absolute right-2 top-2 z-10 opacity-0 transition-opacity duration-150 group-hover/code:opacity-100 focus-visible:opacity-100">Copy</button>
      <pre class="overflow-x-auto bg-base-100/50 p-3 font-mono text-xs leading-relaxed"><code>{source}</code></pre>
    </div>
  {:else if !rendered}
    <div class="p-3 text-xs text-base-content/40">Rendering diagram…</div>
  {/if}
</div>
