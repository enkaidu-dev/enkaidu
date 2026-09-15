<script lang="ts">
  import BlockFrame from "./BlockFrame.svelte";
  import { sanitizeSvg } from "../sanitize";
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
  // Sanitize before {@html} — the source comes from the <template>
  // placeholder (inline) or the raw file body (panel), both of which
  // bypass render_markdown's DOMPurify path.
  let safeSource = $derived(sanitizeSvg(source));
</script>

<BlockFrame
  {language}
  {source}
  rendered={true}
  failed={false}
  {saves}
  {saveBasename}
  {mode}
  {onclose}
  diagramLabel="Diagram"
  codeLabel="Source"
  bind:view
>
  <div class="not-prose flex min-h-full items-center justify-center overflow-x-auto p-3">
    {@html safeSource}
  </div>
</BlockFrame>
