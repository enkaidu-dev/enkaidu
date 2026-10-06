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
   //      • One DOM node per source line (`.gutter-line` / `.code-line`).
   //      • Sticky line-number gutter that stays visible on short lines while
   //        scrolling right (gutter is a single full-height column, not a
   //        per-row cell — see the markup note).
   //      • Syntax highlighting via highlight.js, applied per line.
   //      • Self-contained copy button (no data-copy-code attribute; the
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
    language?: string; // file extension or hljs language code;
     // unknown or empty → "plaintext" fallback
  } = $props();

   // $derived (not const): `language` is a $props value. A plain const
   // captures its initial value and never updates when FilePanel passes a
   // different file on re-open.
  const resolved = $derived(
    language && hljs.getLanguage(language) ? language : "plaintext",
  );

   // Per-line highlight. Each line is highlighted independently; multi-line
   // syntax constructs don't cross the boundary. Phase 2 can fix this.
  const lines = $derived(source.trimEnd().split("\n"));
  const highlighted = $derived(
    lines.map(
      (line) => hljs.highlight(line, { language: resolved }).value || line,
    ),
  );

   // Self-contained copy: copies the raw source, not the HTML. No
   // data-copy-code attribute, so the delegated listener on FilePanel's
   // panel_root never matches this button.
  let copy_chip = $state<HTMLButtonElement | null>(null);
  async function handle_copy(): Promise<void> {
    const ok = await copy_to_clipboard(source.trimEnd());
    if (ok && copy_chip) flash_copied(copy_chip);
  }
</script>

<!--
  source-view: h-full fills the min-h-0 flex-1 wrapper in FilePanel;
  overflow-hidden keeps the copy chip inside the panel. The chip is
  absolutely positioned on source-view, so it stays pinned to the
  top-right of the panel regardless of the inner scroll. source-lines is
  the single scroll box for BOTH axes.

  Gutter layout: the numbers live in ONE full-height sticky column, NOT in a
  per-row cell. A per-row sticky gutter breaks for short lines — its sticky
  containing block is the row, and a min-w-max row is only as wide as its
  own content, so scrolling right past a short row carries its gutter
  off-screen. A single gutter column whose sticky containing block is the
  full scroll width (source-grid is `w-max`, as wide as the widest line)
  keeps every number pinned as the user scrolls right.
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

    <!--
    hljs language-{resolved}: language context for the highlight.js CSS
    cascade — the .hljs-* token classes descend from here.
    source-lines is the scroll box; source-grid (`flex w-max`) is as wide
    as the widest line, so horizontal scroll is real and a sticky gutter
    column inside it pins for every line.
     -->
   <div
    class="hljs language-{resolved}
            source-lines
            h-full overflow-auto
            bg-base-100/50 px-0 py-3
            font-mono text-xs leading-relaxed"
   >
     <div class="source-grid flex w-max">
       <!--
        Gutter column: one sticky element spanning all lines. Opaque
        bg-base-100 slightly contrasts the translucent bg-base-100/50 of
        source-lines — a deliberate, accepted trade-off, and required so
        scrolled code does not show through the sticky gutter. z-10 lifts
        it above the code. select-none stops users dragging across numbers.
        Each gutter-line matches a code-line 1:1 by index.
        -->
       <div
        class="source-gutter
         sticky left-0 z-10
         shrink-0
         min-w-12 pr-3
         text-right
         text-base-content/25
         select-none
         bg-base-100"
       >
        {#each lines as _line, i (i)}
         <div class="gutter-line" aria-hidden="true">{i + 1}</div>
        {/each}
       </div>

       <!--
        Code column: one code-line per source line, `whitespace-pre` so
        long lines don't wrap — they extend source-grid and drive the
        horizontal scroll. Per-line <pre> keeps the .source-lines pre
        override (app.css) relevant: it neutralises the hand-written
        .prose pre bubble in inline mode.
        -->
       <div class="source-code">
        {#each highlighted as html, i (i)}
         <pre class="code-line whitespace-pre">{@html html}</pre>
        {/each}
       </div>
     </div>
   </div>
</div>
