<script lang="ts">
  import BlockFrame from "./BlockFrame.svelte";
  import Markdown from "../Markdown.svelte";
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
</script>

<BlockFrame
  {language}
  {source}
  rendered={true}
  {saves}
  {saveBasename}
  diagramLabel="Preview"
  codeLabel="Source"
  // Preview view: render the fence's markdown with the same component the
  // transcript itself uses, so the preview gets identical prose styling,
  // code highlighting, and (via that inner Markdown's own hydration + copy
  // delegation) nested interactive blocks and copy chips.
  bind:view
>
  <!--
    Deliberate: no not-prose anywhere on this preview body. A not-prose
    ancestor (on the frame or here) would scope the transcript's Tailwind
    Typography rules out of the rendered markdown — headings would collapse
    to body size and all paragraph margins would drop (see the note on the
    BlockFrame root). Leaving this body unscoped is what makes the preview
    inherit the same typography as the rest of the transcript.
  -->
  <div class="p-3">
    <Markdown content={source} />
  </div>
</BlockFrame>
