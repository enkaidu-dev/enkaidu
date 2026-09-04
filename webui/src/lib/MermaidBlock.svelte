<script lang="ts">
  import { mermaid_render } from "../mermaid";

  let { source }: { source: string } = $props();

  let view = $state<"diagram" | "code">("diagram");
  let svg = $state("");
  let failed = $state(false);
  let error = $state("");
  // mermaid is loaded and rendered asynchronously, so the toggle is
  // hidden until there is something definite to show (diagram or a
  // failure). Once known, the state below is plain UI state.
  let rendered = $state(false);

  // mermaid themes are single-scheme (the SVG has colors baked in), so
  // when the OS color scheme flips we re-render the diagram under the
  // other theme. Cheap: the switch is rare and each result is cached.
  let scheme = $state(window.matchMedia("(prefers-color-scheme: dark)"));
  $effect(() => {
    const handler = () => (scheme = window.matchMedia("(prefers-color-scheme: dark)"));
    scheme.addEventListener("change", handler);
    return () => scheme.removeEventListener("change", handler);
  });

  $effect(() => {
    void scheme; // re-run when the OS color scheme changes
    // A re-render (scheme flip) is also a retry: clear a stale failure
    // so a successful render restores the Diagram view.
    if (failed) {
      failed = false;
      error = "";
      view = "diagram";
    }
    let cancelled = false;
    mermaid_render(source)
      .then((diagram) => {
        if (!cancelled) svg = diagram;
      })
      .catch((reason) => {
        if (cancelled) return;
        failed = true;
        error = reason instanceof Error ? reason.message : String(reason);
        view = "code";
      })
      .finally(() => {
        if (!cancelled) rendered = true;
      });
    return () => {
      cancelled = true;
    };
  });
</script>

<!-- Interactive mermaid block: rendered diagram with a Diagram/Code
     toggle. The action row (label left, chips right) is intentionally
     generic so future per-block actions (e.g. "Download") can be
     slotted in without touching the state logic. "Copy source" is
     handled by the Code view wearing the regular fenced-block wrapper
     (see the Code branch below). -->
<div
  class="not-prose my-6 w-full overflow-hidden rounded-lg border border-base/85 text-sm"
>
  <div
    class="flex items-center justify-between gap-2 border-b border-base/85 bg-base-200 px-3 py-1.5"
  >
    <span class="font-mono text-xs text-base-content/50">mermaid</span>
    <div class="flex items-center gap-1">
      {#if rendered}
        {#if !failed}
          <button
            type="button"
            class="action-chip"
            class:active={view === "diagram"}
            aria-pressed={view === "diagram"}
            onclick={() => (view = "diagram")}>Diagram</button>
        {/if}
        <button
          type="button"
          class="action-chip"
          class:active={view === "code"}
          aria-pressed={view === "code"}
          onclick={() => (view = "code")}>Code</button>
      {/if}
    </div>
  </div>

  {#if failed && view === "code"}
    <div
      class="border-b border-base/85 bg-error/10 px-3 py-1.5 text-xs text-error/90"
    >
      Couldn't render diagram: {error}
    </div>
  {/if}

  {#if view === "diagram" && svg}
    <div class="flex justify-center overflow-x-auto p-3">
      {@html svg}
    </div>
  {:else if view === "code" && source}
    <!-- Wears the same wrapper + button markup as a regular fenced block:
         Markdown.svelte's delegated copy handler picks it up for free
         (it watches for [data-copy-code] under .enkaidu-code anywhere in
         the transcript, including hydrated blocks). Mermaid isn't a
         highlight.js language, so the source stays plaintext. -->
    <div class="enkaidu-code group/code relative">
      <button
        type="button"
        data-copy-code
        aria-label="Copy code"
        class="enkaidu-copy absolute right-2 top-2 z-10 opacity-0 transition-opacity duration-150 group-hover/code:opacity-100 focus-visible:opacity-100">Copy</button>
      <pre
        class="overflow-x-auto bg-base-100/50 p-3 font-mono text-xs leading-relaxed"><code>{source}</code></pre>
    </div>
  {:else if !rendered}
    <div class="p-3 text-xs text-base-content/40">Rendering diagram…</div>
  {/if}
</div>
