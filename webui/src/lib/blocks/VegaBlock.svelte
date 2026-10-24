<script lang="ts">
  import BlockFrame from "./BlockFrame.svelte";
  import {
    vega_cache,
    normalize_cache_key,
    record_vega_failure,
    vega_cached_error,
    MAX_SOURCE_BYTES,
    RENDER_TIMEOUT_MS,
    RENDER_TIMEOUT_MESSAGE,
  } from "./registry";
  import { sanitizeSvg } from "../sanitize";
  // Shared bounded-error formatting (kept in mermaid.ts as the one
  // implementation; a shared util import, not renderer-coupling).
  import { render_message } from "../../mermaid";
  import type { BlockProps } from "./types";

  let {
    source,
    language,
    saves = [],
    saveBasename = "source",
    mode = "inline",
    onclose,
  }: BlockProps = $props();

  // Seed synchronously from the cache so a streaming re-mount shows the
  // result (or the recorded failure) instantly, without re-running the
  // renderer. The renderer itself only runs when there is NO recorded
  // outcome for this source — see the effect below.
  // svelte-ignore state_referenced_locally
  const normalizedKey = normalize_cache_key(source);
  const cached = vega_cache.get(normalizedKey);
  // svelte-ignore state_referenced_locally
  const cached_error = vega_cached_error(source);
  let view = $state<"diagram" | "code">(cached_error !== null ? "code" : "diagram");
  // chartLoaded governs the "Rendering chart…" overlay; a known outcome
  // (success or failure) counts as loaded so the overlay never flashes.
  let chartLoaded = $state(cached !== undefined || cached_error !== null);
  let failed = $state(cached_error !== null);
  let error = $state(cached_error ?? "");
  // Sanitize the cached SVG on read — a malicious spec could have cached
  // a dangerous SVG (e.g. with foreignObject or onerror handlers) before
  // this fix was deployed; sanitise at the boundary, not only at write time.
  let initialHtml = cached !== undefined ? sanitizeSvg(cached) : "";

  let container = $state<HTMLDivElement | null>(null);

  // Track the OS color scheme so we can re-render Vega if the theme changes
  let scheme = $state(window.matchMedia("(prefers-color-scheme: dark)"));
  $effect(() => {
    const handler = () => (scheme = window.matchMedia("(prefers-color-scheme: dark)"));
    scheme.addEventListener("change", handler);
    return () => scheme.removeEventListener("change", handler);
  });

  $effect(() => {
    void scheme; // re-render / retry on an OS color-scheme change
    void source;
    if (!container) return;

    // ANTI-STORM STEP. If this source already has a recorded outcome — a
    // successful render sitting in `vega_cache` (seeded above into
    // initialHtml/chartLoaded) or a failure sitting in the memo (seeded
    // above into failed/error) — skip the renderer entirely. The heavy
    // `embed()` must run at most ONCE per source, so the streaming
    // churn's unmount/re-mount can't re-storm the main thread on a bad or
    // huge spec. This is what turns the vega "Stop this page" loop into a
    // single, reported, remembered failure — the same model the mermaid
    // fix used.
    const key = normalize_cache_key(source);
    if (vega_cache.get(key) !== undefined || vega_cached_error(source) !== null) {
      return;
    }

    // Source-size backstop: refuse a pathologically large spec before
    // `embed` sees it (a huge `data` array or a combinatorial layout would
    // otherwise blow up the main-thread render). Record it so the churn
    // doesn't retry.
    if (source.length > MAX_SOURCE_BYTES) {
      const msg = `source too large to render safely (${(source.length / 1024).toFixed(1)} KiB)`;
      record_vega_failure(source, msg);
      failed = true;
      error = msg;
      view = "code";
      chartLoaded = true;
      return;
    }

    // 1. Parse the source as JSON (cheap, synchronous). Invalid JSON is a
    //    known failure — record it and skip the embed.
    let spec: any;
    try {
      spec = JSON.parse(source);
    } catch (e) {
      const msg = "Invalid JSON: " + render_message(e);
      record_vega_failure(source, msg);
      failed = true;
      error = msg;
      view = "code";
      chartLoaded = true;
      return;
    }

    let cancelled = false;

    // 2. Render ONCE, under a best-effort deadline. The deadline bounds an
    //    *asynchronous* slow embed; it cannot interrupt a *synchronous* CPU
    //    burst on the main thread (the same documented gap as mermaid — the
    //    one residual case that needs a Web Worker). Marking the raw embed
    //    handled avoids an unhandled rejection when the deadline wins the race.
    import("vega-embed")
      .then((mod) => {
        if (cancelled) return;
        const embed = mod.default;
        const isDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
        // Force the chart to be responsive to the container width.
        const responsiveSpec = {
          width: "container",
          ...spec,
        };
        const embedded = embed(container!, responsiveSpec, {
          actions: false, // hide vega actions menu
          theme: isDark ? "dark" : undefined,
          renderer: "svg", // high-quality crisp vectors
        });
        embedded.catch(() => {}); // handled: the deadline race may reject first
        return Promise.race([
          embedded,
          new Promise<never>((_res, rej) =>
            setTimeout(() => rej(new Error(RENDER_TIMEOUT_MESSAGE)), RENDER_TIMEOUT_MS),
          ),
        ]);
      })
      .then(() => {
        if (cancelled) return;
        // Extract the generated SVG and cache it (sanitized on write) so the
        // next re-mount is an instant seed instead of a re-embed.
        const svgElement = container?.querySelector("svg");
        if (svgElement) {
          vega_cache.set(key, sanitizeSvg(svgElement.outerHTML));
        }
        chartLoaded = true;
      })
      .catch((err) => {
        if (cancelled) return;
        const msg = render_message(err);
        // Record the failure so subsequent re-mounts short-circuit above
        // instead of re-embedding the same bad spec.
        record_vega_failure(source, msg);
        failed = true;
        error = msg;
        view = "code";
        chartLoaded = true;
      });

    return () => {
      cancelled = true;
    };
  });
</script>

<BlockFrame
  {language}
  {source}
  rendered={true}
  {failed}
  {error}
  diagramLabel="Chart"
  codeLabel="JSON"
  {saves}
  {saveBasename}
  {mode}
  {onclose}
  bind:view
>
  <div
    class="not-prose relative flex w-full justify-center overflow-x-auto p-3 {mode ===
    'panel'
      ? 'h-full'
      : 'min-h-[150px]'}"
  >
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
