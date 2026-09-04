<script lang="ts">
  import BlockFrame from "./BlockFrame.svelte";
  import { vega_cache, normalize_cache_key } from "./registry";

  let { source, language }: { source: string; language: string } = $props();
  let view = $state<"diagram" | "code">("diagram");
  let failed = $state(false);
  let error = $state("");
  
  // Seed state from cache if already rendered in a previous stream chunk
  // svelte-ignore state_referenced_locally
  const normalizedKey = normalize_cache_key(source);
  const cached = vega_cache.get(normalizedKey);
  let chartLoaded = $state(cached !== undefined);
  let initialHtml = cached ?? "";
  
  let container = $state<HTMLDivElement | null>(null);

  // Track the OS color scheme so we can re-render Vega if the theme changes
  let scheme = $state(window.matchMedia("(prefers-color-scheme: dark)"));
  $effect(() => {
    const handler = () => (scheme = window.matchMedia("(prefers-color-scheme: dark)"));
    scheme.addEventListener("change", handler);
    return () => scheme.removeEventListener("change", handler);
  });

  $effect(() => {
    void scheme; // trigger re-render on OS theme changes
    if (!container) return;

    if (failed) {
      failed = false;
      error = "";
      view = "diagram";
    }

    let cancelled = false;

    // 1. Attempt to parse the source as JSON
    let spec: any;
    try {
      spec = JSON.parse(source);
    } catch (e: any) {
      failed = true;
      error = "Invalid JSON: " + e.message;
      chartLoaded = true;
      view = "code";
      return;
    }

    // 2. Load vega-embed and render
    import("vega-embed")
      .then((mod) => {
        if (cancelled) return;
        const embed = mod.default;
        const isDark = window.matchMedia("(prefers-color-scheme: dark)").matches;

        // Force vega-lite chart to be responsive to container width
        const responsiveSpec = {
          width: "container",
          ...spec,
        };

        // If we have cached HTML, we empty the container before vega re-binds
        if (cached && container) {
          container.innerHTML = "";
        }

        return embed(container!, responsiveSpec, {
          actions: false, // hide vega actions menu
          theme: isDark ? "dark" : undefined,
          renderer: "svg", // high-quality crisp vectors
        });
      })
      .then(() => {
        if (cancelled) return;
        
        // Extract the generated SVG to cache it for seamless streaming
        const svgElement = container?.querySelector("svg");
        if (svgElement) {
          vega_cache.set(normalizedKey, svgElement.outerHTML);
        }
        
        chartLoaded = true;
      })
      .catch((err) => {
        if (cancelled) return;
        failed = true;
        error = err instanceof Error ? err.message : String(err);
        chartLoaded = true;
        view = "code";
      });

    return () => {
      cancelled = true;
    };
  });
</script>

<BlockFrame {language} {source} rendered={true} {failed} {error} diagramLabel="Chart" codeLabel="JSON" bind:view>
  <div class="flex justify-center overflow-x-auto p-3 w-full relative min-h-[150px]">
    {#if !chartLoaded && !failed}
      <div class="absolute inset-0 flex items-center justify-center bg-base-100 text-xs text-base-content/40">
        Rendering chart…
      </div>
    {/if}
    <div bind:this={container} class="w-full max-w-full overflow-hidden" class:opacity-0={!chartLoaded}>
      {@html initialHtml}
    </div>
  </div>
</BlockFrame>
