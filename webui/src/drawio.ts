// Anti-lockup + memo layer for drawio rendering.
//
// This wraps the vendored drawio_svg translator
// (`./drawio_svg/translate.ts`), derived from the dsh-drawio translate
// module (Apache-2.0 — see `./dsh-drawio/LICENSE`; the file is derivative
// work and is re-licensed under its Apache-2.0 terms). The translator is
// DOM-free, synchronous, and dependency-free. Its API is small and total
// (never throws):
//
//   `sniffDrawio(text) → 'none' | 'incomplete' | 'complete'`
//   `renderDrawio(xml, options) → { ok: true, pages } | { ok: false, error }`
//
// One `RenderedPage` per `<diagram>` page; each carries a standalone SVG
// (width/height/viewBox set), a fidelity grade (`full` / `partial` /
// `none`), and a diagnostics list. It renders a documented subset of
// drawio and reports everything outside it — unsupported shapes become
// dashed placeholders or are omitted — which is the intended "preview
// here, open in Draw.io for full fidelity" behavior.
//
// The layering mirrors `mermaid.ts`: a success cache, a symmetric failure
// memo, in-flight coalescing, and a source-size backstop. The success
// cache is what makes the streaming churn in Markdown.svelte (which
// re-mounts the block on nearly every fragment) near-instant; the
// failure memo is what stops a bad/giant source from being re-rendered on
// every re-mount and storming the main thread.
//
// The translator is dynamically imported only when a transcript actually
// contains a finished diagram, keeping this module out of the base bundle
// for the common case of chat text. That lazy boundary is also why the
// fence sniff in `registry.ts` keeps its own cheap regex instead of
// calling the module's `sniffDrawio` — a static import there would pull
// the translator into the base bundle.
//
// One honest limitation carried over from the translator: a *compressed*
// .drawio (`<diagram compressed="1">`, base64+zlib) is NOT decompressed
// here — `renderDrawio` only decompresses via the synchronous
// `options.inflateRaw` hook, and the browser's `DecompressionStream` is
// async, so a compressed page resolves to `{ ok: false, error }`
// ("page … is compressed"), which surfaces in the "Couldn't render
// diagram:" strip. AI-generated .drawio is plain, uncompressed XML, which
// is the supported case.

import { sanitizeSvg } from "./lib/sanitize";
import { render_message } from "./mermaid";

// Re-export so DrawioBlock has one import site for render + error formatting.
export { render_message };

type TranslateModule = typeof import("./drawio_svg/translate");

// ---- lazy load ----------------------------------------------------------
let drawio_promise: Promise<TranslateModule> | undefined;

function load_drawio(): Promise<TranslateModule> {
  if (!drawio_promise) {
    drawio_promise = import("./drawio_svg/translate");
  }
  return drawio_promise;
}

// ---- caches -------------------------------------------------------------
const MAX_CACHE_ENTRIES = 50;

// Backstop against a pathological source (e.g. an LLM that dumps a
// multi-megabyte diagram) blowing up the layout / XML parse before we
// even render. A size guard, NOT a loop guard — a small source that
// still wedges the renderer is not caught here and would need the Web
// Worker isolation layer (same documented gap as mermaid.ts).
const MAX_SOURCE_BYTES = 256 * 1024;

// Normalize key so line-ending / trailing-whitespace churn doesn't cache
// the same diagram under different keys.
function key(source: string): string {
  return source.replace(/\r\n/g, "\n").trim();
}

// The rendered SVG is theme-agnostic (per-cell fill/stroke come from the
// diagram itself; we render a transparent background), so a source-only
// key is correct — unlike mermaid, it does NOT need a theme part.
const rendered_cache = new Map<string, string>();

// Symmetric to rendered_cache. The core anti-lockup fix: a source that
// fails to render is remembered, so the streaming churn never re-sends it
// to the translator on each re-mount.
const failing_cache = new Map<string, string>();

// In-flight render promises, keyed the same way. Concurrent re-mounts of
// the same source coalesce onto ONE attempt.
const inflight = new Map<string, Promise<string>>();

// Gradient/defs id prefix, unique per rendered source. The renderer
// prefixes its generated ids with `idPrefix` + page index, so two
// *different* diagrams inlined in one document (e.g. two drawio blocks in
// a single transcript) must not share a prefix or their <defs> ids would
// collide. Assigned synchronously once per attempt, so it is stable across
// the streaming re-mounts that hit the cache.
let id_seq = 0;

function create_render_error(message: string): Error {
  const e = new Error(message);
  e.name = "DrawioRenderError";
  return e;
}

// Render `source` to a standalone SVG string. Resolves with the
// (sanitized) SVG or rejects with a DrawioRenderError carrying a bounded
// message. Memoized + failure-remembered as described above.
export async function drawio_render(source: string): Promise<string> {
  const k = key(source);

  // 1. Success cache: instant on every streaming re-mount.
  const cached = rendered_cache.get(k);
  if (cached !== undefined) {
    return cached;
  }

  // 2. Failure memo: don't re-enter the translator for a known-bad source.
  const remembered = failing_cache.get(k);
  if (remembered !== undefined) {
    throw create_render_error(remembered);
  }

  // 3. Coalesce onto an in-flight attempt for this source.
  const existing = inflight.get(k);
  if (existing) {
    return existing;
  }

  // 4. Size backstop: refuse absurdly large sources outright and remember
  //    it so the churn doesn't retry.
  if (source.length > MAX_SOURCE_BYTES) {
    const msg = `source too large to render safely (${(source.length / 1024).toFixed(1)} KiB)`;
    failing_cache.set(k, msg);
    throw create_render_error(msg);
  }

  const attempt: Promise<string> = (async () => {
    try {
      const idPrefix = `dio${id_seq++}`;
      const mod = await load_drawio();
      // renderDrawio is total: structurally-invalid input (not an
      // mxfile/mxGraphModel root), a compressed page without an inflater,
      // or zero parseable pages resolve to { ok: false, error } instead of
      // throwing. background:false keeps the diagram transparent so it
      // sits in the app's theme; unsupported shapes fall through to the
      // translator's dashed placeholder boxes (reported as diagnostics).
      const result = mod.renderDrawio(source, { background: false, idPrefix });
      if (!result.ok) {
        throw new Error(result.error);
      }
      // As before, only the first page of a multi-page document renders.
      const page = result.pages[0];
      if (!page) {
        throw new Error("no parseable diagram found in the drawio source");
      }
      if (page.fidelity === "none") {
        // Nothing on the page was drawn (empty page, or every cell
        // invisible / omitted) — an empty canvas is not a useful preview.
        throw new Error("no renderable content found in the first drawio page");
      }
      // Defense in depth: the renderer emits plain SVG (no scripts, no
      // foreignObject, no external references), but sanitize again so
      // nothing can carry a handler or a smuggled element through the
      // {@html} injection.
      return sanitizeSvg(page.svg);
    } catch (reason) {
      throw create_render_error(render_message(reason));
    }
  })();

  inflight.set(k, attempt);
  attempt.then(
    (svg) => {
      inflight.delete(k);
      if (rendered_cache.size >= MAX_CACHE_ENTRIES) {
        const oldest = rendered_cache.keys().next().value;
        if (oldest !== undefined) {
          rendered_cache.delete(oldest);
        }
      }
      rendered_cache.set(k, svg);
    },
    (reason) => {
      inflight.delete(k);
      const msg = render_message(reason);
      if (failing_cache.size > MAX_CACHE_ENTRIES * 4) {
        const oldest = failing_cache.keys().next().value;
        if (oldest !== undefined) {
          failing_cache.delete(oldest);
        }
      }
      failing_cache.set(k, msg);
    },
  );

  return attempt;
}

// Synchronous "is it already rendered?" lookup. DrawioBlock seeds its
// initial state from this so a streaming re-mount shows the diagram
// immediately instead of flashing through "Rendering diagram…" / code.
export function drawio_cached(source: string): string | null {
  return rendered_cache.get(key(source)) ?? null;
}

// Symmetric to drawio_cached: a synchronous "is this source already known
// to fail?" lookup, so a re-mount of a known-bad source skips the
// translator entirely instead of re-attempting it.
export function drawio_cached_error(source: string): string | null {
  return failing_cache.get(key(source)) ?? null;
}
