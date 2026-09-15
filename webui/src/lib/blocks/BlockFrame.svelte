<script lang="ts">
  import type { Snippet } from "svelte";
  import { download, mimeForExt, type SaveOption, type SaveContext } from "./save";
  import type { BlockProps } from "./types";

  // BlockFrame additionally owns the view toggle state (a block passes it
  // through with bind:view) and wraps the block's content (children).
  let {
    language,
    source,
    rendered = true,
    failed = false,
    error = "",
    view = $bindable("diagram"),
    diagramLabel = "Diagram",
    codeLabel = "Source",
    saves = [],
    saveBasename = "source",
    mode = "inline",
    onclose,
    children,
  }: BlockProps & {
    view?: "diagram" | "code";
    rendered?: boolean;
    failed?: boolean;
    error?: string;
    diagramLabel?: string;
    codeLabel?: string;
    children?: Snippet;
  } = $props();

  // The element the rendered content lives in; save options read the live
  // rendered DOM through SaveContext.frame. Inline: the frame root itself.
  // Panel: the filling body div (there is no floating frame at all).
  let contentElement = $state<HTMLDivElement | null>(null);

  // The save chips the renderer offers, filtered to those currently
  // available (e.g. the rendered-SVG save only while an <svg> is mounted
  // in the diagram view). Re-evaluated with a 100ms debounce so the
  // streaming churn (the @html is replaced wholesale and the block
  // re-mounts) doesn't make the chips flicker.
  let availableSaves = $state<SaveOption[]>([]);
  $effect(() => {
    void source; // re-evaluate when the content changes (retry / re-render)
    void view; // the rendered-SVG save is only available in the diagram view
    void rendered;
    void failed;
    void contentElement;
    if (!contentElement) {
      availableSaves = [];
      return;
    }
    const ctx: SaveContext = { source, language, frame: contentElement };
    const timer = setTimeout(() => {
      availableSaves = saves.filter((s) => (s.available ? s.available(ctx) : true));
    }, 100);
    return () => clearTimeout(timer);
  });

  // Download a single save option's content as <saveBasename>.<ext>.
  function handle_save(option: SaveOption): void {
    if (!contentElement) return;
    const content = option.produce({ source, language, frame: contentElement });
    // The rendered-SVG producer may yield "" if the <svg> vanished
    // between the availability check and the click; don't download an
    // empty file.
    if (typeof content === "string" && content.trim() === "") return;
    const mime = option.mime ?? mimeForExt(option.ext);
    download(`${saveBasename}.${option.ext}`, content, mime);
  }
</script>

<!--
  The action chips are identical in both modes; only the chrome around
  them differs. Shared as a local snippet so inline and panel can never
  drift apart.
-->
{#snippet chips()}
  {#if rendered}
    {#if !failed}
      <button
        type="button"
        class="action-chip"
        class:active={view === "diagram"}
        aria-pressed={view === "diagram"}
        onclick={() => (view = "diagram")}
      >{diagramLabel}</button>
    {/if}
    <button
      type="button"
      class="action-chip"
      class:active={view === "code"}
      aria-pressed={view === "code"}
      onclick={() => (view = "code")}
    >{codeLabel}</button>
    {#if availableSaves.length > 0}
      <div class="ml-2 flex items-center gap-1">
        {#each availableSaves as option (option)}
          <button
            type="button"
            class="action-chip"
            onclick={() => handle_save(option)}
          >Save {option.label}</button>
        {/each}
      </div>
    {/if}
  {/if}
{/snippet}

{#if mode === "panel"}
  <!--
    Panel mode (file viewer): deliberately a FRAGMENT of two top-level
    nodes — the bar row and the body. FilePanel mounts blocks into a
    `display: contents` wrapper inside its flex-col aside, so both nodes
    become flex items of the panel itself: exactly ONE bar along the top
    (file path label + this block's view toggle + save chips + the panel's
    close, sharing one row) with the content filling the rest. No inner
    frame, no height cap. The typography gotcha for `prose` is moot here
    (the panel has no .prose ancestor).
  -->
  <div
    class="flex shrink-0 items-center gap-2 border-b border-base bg-base-200 px-3 py-2"
  >
    <span class="min-w-0 flex-1 truncate font-mono text-xs" title={language}>
      {language}
    </span>
    <div class="flex shrink-0 items-center gap-1">
      {@render chips()}
    </div>
    <button
      type="button"
      class="action-chip shrink-0"
      onclick={() => onclose?.()}
      title="Close panel"
      aria-label="Close panel"
    >
      ✕
    </button>
  </div>
  {#if failed && view === "code"}
    <div class="shrink-0 border-b border-base/85 bg-error/10 px-3 py-1.5 text-xs text-error/90">
      Couldn't render diagram: {error}
    </div>
  {/if}
  <div class="relative min-h-0 flex-1 overflow-auto" bind:this={contentElement}>
    {#if view === "diagram" && rendered && !failed}
      {@render children?.()}
    {:else if view === "code" && source}
      <div class="enkaidu-code group/code relative h-full not-prose">
        <button
          type="button"
          data-copy-code
          aria-label="Copy code"
          class="enkaidu-copy absolute right-2 top-2 z-10 opacity-0 transition-opacity duration-150 group-hover/code:opacity-100 focus-visible:opacity-100"
        >Copy</button>
        <pre
          class="h-full overflow-auto bg-base-100/50 p-3 font-mono text-xs leading-relaxed whitespace-pre-wrap wrap-break-word"
        ><code>{source}</code></pre>
      </div>
    {:else if !rendered}
      <div class="p-3 text-xs text-base-content/40">Rendering diagram…</div>
    {/if}
  </div>
{:else}
  <!--
    Inline mode (transcript): the floating framed box, unchanged. Root
    deliberately carries NO `not-prose`: Tailwind Typography's generated
    rules all include an `:not(:where([class~=not-prose], [class~=not-prose] *))`
    exclusion guard, so a not-prose ancestor would scope the block's
    contents OUT of prose typing; the views that must stay clean from
    prose typing wrap themselves instead.
  -->
  <div
    bind:this={contentElement}
    class="my-6 w-full overflow-hidden rounded-lg border border-base/85 text-sm"
  >
    <div
      class="flex items-center justify-between gap-2 border-b border-base/85 bg-base-200 px-3 py-1.5"
    >
      <span class="font-mono text-xs text-base-content/50">{language}</span>
      <div class="flex items-center gap-1">
        {@render chips()}
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
      <div class="enkaidu-code group/code relative not-prose">
        <button
          type="button"
          data-copy-code
          aria-label="Copy code"
          class="enkaidu-copy absolute right-2 top-2 z-10 opacity-0 transition-opacity duration-150 group-hover/code:opacity-100 focus-visible:opacity-100"
        >Copy</button>
        <pre class="overflow-x-auto bg-base-100/50 p-3 font-mono text-xs leading-relaxed"><code>{source}</code></pre>
      </div>
    {:else if !rendered}
      <div class="p-3 text-xs text-base-content/40">Rendering diagram…</div>
    {/if}
  </div>
{/if}
