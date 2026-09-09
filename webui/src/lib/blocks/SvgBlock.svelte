<script lang="ts">
  import BlockFrame from "./BlockFrame.svelte";
  import { sanitizeSvg } from "../sanitize";
  import type { SaveOption } from "./save";

  let {
    source,
    language,
    saves = [],
    saveBasename = "source",
    }: {
    source: string;
    language: string;
    saves?: SaveOption[];
    saveBasename?: string;
    } = $props();
  let view = $state<"diagram" | "code">("diagram");
    // Sanitize before {@html} — the raw source comes from a <template>
    // in Markdown.svelte and bypasses render_markdown's DOMPurify path.
  let safeSource = $derived(sanitizeSvg(source));
</script>

<BlockFrame {language} {source} rendered={true} failed={false} {saves} {saveBasename} bind:view>
    <div class="not-prose flex justify-center overflow-x-auto p-3">
      {@html safeSource}
    </div>
</BlockFrame>
