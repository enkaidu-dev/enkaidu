<script lang="ts">
  import {
    mermaid_cached,
    mermaid_cached_error,
    mermaid_render,
    render_message,
  } from "../../mermaid";
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
  // component is recreated on nearly every fragment (the @html is
  // replaced wholesale and the re-mounted placeholder starts fresh);
  // starting already-rendered from cache means those re-creations show
  // the diagram immediately instead of flashing through code fallback
  // and "Rendering diagram…". The first render still goes through
  // mermaid_render below and populates the cache; the effect then keeps
  // the values current afterwards.
  // svelte-ignore state_referenced_locally
  const cached = mermaid_cached(source);
  // A source that already failed on a previous mount (during this stream)
  // is remembered, so re-mounts skip the renderer and show the "Couldn't
  // render" strip instantly instead of re-storming the main thread.
  // svelte-ignore state_referenced_locally
  const cached_error = mermaid_cached_error(source);
  let view = $state<"diagram" | "code">(cached_error !== null ? "code" : "diagram");
  let svg = $state(cached ?? "");
  let failed = $state(cached_error !== null);
  let error = $state(cached_error ?? "");
  // mermaid is loaded and rendered asynchronously, so the toggle is
  // hidden until there is something definite to show (diagram or a
  // failure). Once known, the state below is plain UI state. A
  // remembered failure counts as "known" too.
  let rendered = $state(cached !== null || cached_error !== null);

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
    void scheme; // re-render when the OS color scheme changes
    void source; // re-render when the source changes
    // If this exact source+theme is already known to fail, do NOT re-enter
    // the renderer: the seeding above already reflected the failure, so
    // re-running would only re-storm the main thread during streaming. A
    // scheme flip changes the cache key (the theme part), so a flip
    // naturally re-renders under the new scheme's key below.
    if (mermaid_cached_error(source) !== null) {
      rendered = true;
      return;
    }
    // A fresh attempt (not known-failed): a re-render doubles as a retry,
    // so clear any prior failure — a successful render restores Diagram.
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
        if (!cancelled) {
          console.error("Failed to render mermaid diagram", render_message(reason));
          failed = true;
          error = render_message(reason);
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
  bind:view
>
  <!-- min-h-full is inert inline (auto-height ancestor) and makes the
       diagram fill + center vertically in the panel -->
  <div class="not-prose flex min-h-full items-center justify-center overflow-x-auto p-3">
    {@html svg}
  </div>
</BlockFrame>
