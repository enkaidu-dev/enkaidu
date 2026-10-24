<script lang="ts">
  import {
    drawio_cached,
    drawio_cached_error,
    drawio_render,
    render_message,
  } from "../../drawio";
  import BlockFrame from "./BlockFrame.svelte";
  import type { BlockProps } from "./types";

  let {
    source,
    language,
    saves = [],
    saveBasename = "source",
    mode = "inline",
    onclose,
  }: BlockProps = $props();

  // Seed from the render cache when possible. During streaming this
  // component is recreated on nearly every fragment (the @html is replaced
  // wholesale and the re-mounted placeholder starts fresh); starting
  // already-rendered from cache means those re-creations show the diagram
  // immediately instead of flashing through "Rendering diagram…". A
  // remembered failure seeds the failed/code view instead.
  // svelte-ignore state_referenced_locally
  const cached = drawio_cached(source);
  // svelte-ignore state_referenced_locally
  const cached_error = drawio_cached_error(source);
  let view = $state<"diagram" | "code">(cached_error !== null ? "code" : "diagram");
  let svg = $state(cached ?? "");
  let failed = $state(cached_error !== null);
  let error = $state(cached_error ?? "");
  // drawio is loaded + rendered asynchronously (a lazy import), so the
  // toggle is hidden until there is something definite to show. Once known,
  // the state below is plain UI state; a remembered failure counts as known.
  let rendered = $state(cached !== null || cached_error !== null);

  $effect(() => {
    void source;
    // If this exact source is already known to fail, do NOT re-enter the
    // translator: the seeding above already reflected the failure, so
    // re-running would only re-storm the main thread during streaming.
    if (drawio_cached_error(source) !== null) {
      rendered = true;
      return;
    }
    // A fresh attempt (not known-failed): a re-render doubles as a retry, so
    // clear any prior failure — a successful render restores the diagram.
    if (failed) {
      failed = false;
      error = "";
      view = "diagram";
    }
    let cancelled = false;
    drawio_render(source)
      .then((out) => {
        if (!cancelled) svg = out;
      })
      .catch((reason) => {
        if (!cancelled) {
          const m = render_message(reason);
          console.error("Failed to render drawio diagram", m);
          failed = true;
          error = m;
          view = "code";
        }
      })
      .finally(() => {
        if (!cancelled) rendered = true;
      });
    return () => {
      cancelled = true;
    };
  });
</script>

<BlockFrame
  {language}
  {source}
  {rendered}
  {failed}
  {error}
  {saves}
  {saveBasename}
  {mode}
  {onclose}
  diagramLabel="Diagram"
  codeLabel="Source"
  bind:view
>
  <!-- min-h-full is inert inline (auto-height ancestor) and makes the
       diagram fill/center vertically in the panel. The wrapper carries
       .enkaidu-drawio; the renderer emits a standalone <svg> with
       intrinsic width/height + viewBox, and the .enkaidu-drawio rule in
       app.css overrides that intrinsic size so the diagram scales to the
       container. The rule lives in the global stylesheet because the
       <svg> arrives via {@html} and a scoped selector would flag as
       unused. -->
  <div
    class="not-prose enkaidu-drawio flex min-h-full flex-col items-center
      justify-center gap-2 overflow-x-auto p-3"
  >
    {#if svg}
      <div class="w-full" style="width:100%">
        {@html svg}
      </div>
    {/if}
    <!-- The translator renders a subset of drawio shapes; unsupported ones
         show as dashed placeholder boxes (drawn by the translator, not
         synthesised here). Note the preview is approximate and that the
         full-experience path is opening the saved .drawio in diagram.net /
         Draw.io. -->
    <p
      class="mx-auto max-w-2xl text-center text-xs text-base-content/50
        leading-snug"
    >
      Preview — unsupported shapes render as placeholders. Save and open the
      .drawio in Draw.io for full fidelity.
    </p>
  </div>
</BlockFrame>
