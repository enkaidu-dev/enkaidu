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

    Long previews are height-capped and scroll, using the shared
    --scrollable-max-h custom property from app.css (0.8 × (viewport −
    prompt bar height), floor 12rem — the exact same cap the code sources
    get via the `.prose pre` rule, so the two can never drift apart).
    Rendered views of the *other* blocks (mermaid/svg/vega diagrams and
    tables) intentionally have no cap — cropping diagrammatic content to a
    scroll window isn't useful, while flowing text and code are exactly the
    kinds of content that benefit.
  -->
  <div class="max-h-(--scrollable-max-h) overflow-y-auto p-3">
    <Markdown content={source} />
  </div>
</BlockFrame>
