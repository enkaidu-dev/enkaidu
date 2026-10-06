<script lang="ts">
   // SourceView — per-line highlighted source renderer.
   //
   // Used by FilePanel for files that have no registered block renderer.
   // Replaces the single-blob  `highlight_source(…)` + `<pre>`  path with a
   // structured per-line DOM so that a later phase can layer diff annotations
   // (per-line background, gutter indicators, show/hide removed lines) on top
   // of the line structure without replacing the rendering path.
   //
   // Phase 1 goals:
   //    • One DOM node per source line (`.source-line`).
   //    • Syntax highlighting via highlight.js, applied per line.
   //    • Self-contained copy button (no data-copy-code attribute; the
   //     delegated handler in copy.ts would need a <pre> which this
   //     structure does not provide, so we call copy_to_clipboard directly).
   //
   // Known Phase 1 limitation: syntax that spans multiple source lines
   // (block comments, multi-line string literals) is not highlighted across
   // the boundary. Phase 2 can replace the per-line highlight with a
   // single-pass highlight + line-split, or use hljs.highlightAll on a
   // pre-built DOM tree, for full fidelity.

  import hljs from "highlight.js/lib/common";
  import { copy_to_clipboard, flash_copied } from "../copy";

  let {
    source,
    language = "",
    }: {
    source: string;
    language?: string;    // file extension or hljs language code;
    // unknown or empty → "plaintext" fallback
    } = $props();

    // $derived (not const): `language` is a $props value. A plain const
    // here captures its initial value and never updates when FilePanel
    // passes a different file on re-open.
  const resolved = $derived(
   language && hljs.getLanguage(language) ? language : "plaintext",
    );

    // Per-line highlight. Each line is highlighted independently; this is the
    // trade-off noted above — multi-line syntax constructs don't highlight
    // across the boundary. The per-line DOM structure is in place for Phase 2
    // to replace this with a single-pass highlight + line-boundary split.
  const lines = $derived(source.trimEnd().split("\n"));
  const highlighted = $derived(
    lines.map((line) =>
      hljs.highlight(line, { language: resolved }).value || line
    ),
   );

    // Self-contained copy: copies the raw source (not the HTML). No
    // data-copy-code attribute, so the delegated listener on FilePanel's
    // panel_root never matches this button.
  let copy_chip = $state<HTMLButtonElement | null>(null);
  async function handle_copy(): Promise<void> {
    const ok = await copy_to_clipboard(source.trimEnd());
    if (ok && copy_chip) flash_copied(copy_chip);
    }
</script>

    <!--
      h-full on the root ensures it fills the `min-h-0 flex-1` wrapper in
      FilePanel; overflow-hidden clips the copy button to the header area
      while source-lines handles its own scrolling (h-full + overflow-auto).
    -->
   <div
    class="source-view
      group/code relative
      not-prose
      h-full overflow-hidden"
    >
     <button
      bind:this={copy_chip}
      type="button"
      aria-label="Copy code"
      class="enkaidu-copy absolute right-2 top-2 z-10 opacity-0
             transition-opacity duration-150
             group-hover/code:opacity-100 focus-visible:opacity-100"
      onclick={handle_copy}
     >
      Copy
     </button>
     <div
      class="hljs language-{resolved}
            source-lines
            h-full overflow-auto
            bg-base-100/50 p-3
            font-mono text-xs leading-relaxed
            whitespace-pre-wrap wrap-break-word"
     >
      {#each highlighted as html, i (i)}
       <div class="source-line">{@html html}</div>
      {/each}
     </div>
   </div>
