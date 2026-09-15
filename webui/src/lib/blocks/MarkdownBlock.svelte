<script lang="ts">
  import BlockFrame from "./BlockFrame.svelte";
  import Markdown from "../Markdown.svelte";
  import type { BlockProps } from "./types";

  let {
    source,
    language,
    saves = [],
    saveBasename = "source",
    mode = "inline",
    onclose,
  }: BlockProps = $props();

  let view = $state<"diagram" | "code">("diagram");
</script>

<BlockFrame
  {language}
  {source}
  rendered={true}
  {saves}
  {saveBasename}
  {mode}
  {onclose}
  diagramLabel="Preview"
  codeLabel="Source"
  bind:view
>
  <!--
    Deliberate: no not-prose anywhere on this preview body. A not-prose
    ancestor (on the frame or here) would scope the transcript's Tailwind
    Typography rules out of the rendered markdown — headings would
    collapse to body size and all paragraph margins would drop (see the
    note on the BlockFrame root). Leaving this body unscoped is what
    makes the preview inherit the same typography as the rest of the
    transcript.

    Inline, long previews are height-capped and scroll using the shared
    --scrollable-max-h custom property (the exact same cap the code
    sources get via the `.prose pre` rule, so the two can never drift
    apart); the inner Markdown keeps re-rendering during streaming
    without growing the transcript. In panel mode the body already has a
    definite height (it is the panel's flex-1), so the preview just fills
    and scrolls inside it — no extra cap.
  -->
  <div
    class="overflow-y-auto p-3 {mode === 'panel'
      ? 'h-full'
      : 'max-h-(--scrollable-max-h)'}"
  >
    <Markdown content={source} />
  </div>
</BlockFrame>
