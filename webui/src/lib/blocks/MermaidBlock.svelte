<script lang="ts">
  import { mermaid_cached, mermaid_render } from "../../mermaid";
  import BlockFrame from "./BlockFrame.svelte";

  let { source, language }: { source: string; language: string } = $props();

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
  let view = $state<"diagram" | "code">("diagram");
  let svg = $state(cached ?? "");
  let failed = $state(false);
  let error = $state("");
  // mermaid is loaded and rendered asynchronously, so the toggle is
  // hidden until there is something definite to show (diagram or a
  // failure). Once known, the state below is plain UI state.
  let rendered = $state(cached !== null);

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

<BlockFrame {language} {source} {rendered} {failed} {error} bind:view>
  <div class="flex justify-center overflow-x-auto p-3">
    {@html svg}
  </div>
</BlockFrame>
