// Anti-lockup layering for mermaid rendering.
//
// A diagram whose source is a syntax error (or a pathological input) can
// wedge mermaid's render() on the MAIN thread. Because that blocks the
// event loop, a .catch on the render promise cannot fire until the loop
// unwinds — so a pure "catch the error" approach cannot stop the tab from
// freezing. Three defenses here, in order, shrink the blast radius; a true
// synchronous infinite loop of a *small* source is the one case none of
// them catch, and that needs the Web Worker isolation layer (not yet
// added — see RENDER_TIMEOUT_MS and the note there):
//
//   1. failure memo  — a source that already failed is remembered per
//                      source+theme, so the streaming re-mount churn in
//                      Markdown.svelte never re-sends it to the renderer
//                      (without this, a per-fragment-rejected diagram is
//                      re-rendered on every fragment = a sustained storm).
//   2. coalescing    — concurrent re-mounts of the same source share ONE
//                      in-flight attempt instead of each starting a heavy
//                      synchronous render.
//   3. size backstop — absurdly large sources are refused before the
//                      renderer sees them (stops O(n^2)/exponential layout).
//
// mermaid is dynamically imported only when a transcript actually
// contains a finished diagram — it is a large dependency and we don't
// want it in the base bundle for the common case of chat text.
//
// `mermaid_render(source)` returns the SVG string for `source`, rendered
// under the theme matching the OS color scheme. The cache is keyed by
// source + theme: during streaming, every fragment re-parses the
// surrounding markdown and Svelte replaces the rendered HTML, so the same
// diagram gets re-hydrated repeatedly. Returning the already-rendered SVG
// instead of re-rendering each time keeps that near-instant and
// flicker-free.
type MermaidModule = typeof import("mermaid").default;

let mermaid_promise: Promise<MermaidModule> | undefined;

function load_mermaid(): Promise<MermaidModule> {
  if (!mermaid_promise) {
    mermaid_promise = import("mermaid").then((mod) => mod.default);
  }
  return mermaid_promise;
}

const MAX_CACHE_ENTRIES = 50;
// Key is "source\x00theme" — the rendered SVG has its colors baked in,
// so a light-mode render must not be served once the OS flips to dark.
const rendered_cache = new Map<string, string>();

// Failure memo, keyed exactly like the success cache. This is the core
// anti-lockup fix: a source that fails to render is remembered, so the
// streaming churn (Markdown.svelte re-mounts the block on almost every
// fragment) never re-sends it to the renderer. Without it, a
// slow-but-eventually-failing diagram — or one that errors on every
// attempt — is re-rendered on every fragment, a sustained main-thread
// storm that is what eventually trips Firefox's "Stop this page."
const failing_cache = new Map<string, string>();

// In-flight render promises, keyed the same way. Concurrent re-mounts of
// the same source within a burst coalesce onto ONE attempt instead of
// each starting a heavy synchronous render.
const inflight = new Map<string, Promise<string>>();

// Backstop against a pathological source (e.g. an LLM that dumps a
// multi-megabyte "diagram") blowing up the layout before we even ask
// mermaid. A size guard, NOT a loop guard — a small source that still
// loops the renderer is not caught here and needs the Web Worker.
const MAX_SOURCE_BYTES = 256 * 1024;

// Best-effort deadline for a single render. For an asynchronous render that
// yields to the event loop, this frees the page after the deadline. It
// CANNOT interrupt a synchronous infinite loop (the main thread is wedged
// and the timer can't fire until the loop unwinds) — that is why a true
// hang still needs the Web Worker isolation layer. Documented as a gap.
const RENDER_TIMEOUT_MS = 10000;

let diagram_id = 0;

// Build a render error with a bounded message so a pathological source or a
// giant failure can't blow up a console.error or the UI's error label.
function create_render_error(message: string): Error {
  const e = new Error(message);
  e.name = "MermaidRenderError";
  return e;
}

// Render a render failure into a bounded, human-readable string, safe for
// both console.error and the "Couldn't render diagram:" strip. Guards
// against circular / huge / non-Error rejection values.
export function render_message(err: unknown): string {
  let s: string;
  if (err instanceof Error) {
    s = err.message;
  } else if (err && typeof err === "object") {
    try {
      s = JSON.stringify(err);
    } catch {
      s = String(err);
    }
  } else {
    s = String(err);
  }
  return s.length > 500 ? s.slice(0, 500) + "…" : s;
}

// mermaid only ships fixed single-scheme themes; we follow the OS
// setting so diagrams sit well in both app themes. "neutral" and "dark"
// are chosen because they are the low-chroma, gray-based pair that
// matches the app's warm palette better than the stock "default/forest".
// (The narrow return type is mermaid's literal union for initialize().)
type MermaidTheme = "dark" | "neutral";

function current_mermaid_theme(): MermaidTheme {
  return window.matchMedia("(prefers-color-scheme: dark)").matches
    ? "dark"
    : "neutral";
}

export async function mermaid_render(source: string): Promise<string> {
  const theme = current_mermaid_theme();
  const cache_key = source + "\x00" + theme;

  // 1. Success cache: pixel-perfect, instant on every streaming re-mount.
  const cached = rendered_cache.get(cache_key);
  if (cached !== undefined) {
    return cached;
  }

  // 2. Failure memo: don't re-enter the renderer for a source that already
  //    failed — this is what stops the streaming churn from re-storming
  //    the main thread on a known-bad diagram.
  const remembered = failing_cache.get(cache_key);
  if (remembered !== undefined) {
    throw create_render_error(remembered);
  }

  // 3. Coalesce: a concurrent re-mount is already rendering this source.
  //    Join its promise rather than starting a second heavy render.
  const existing = inflight.get(cache_key);
  if (existing) {
    return existing;
  }

  // 4. Backstop: refuse absurdly large sources outright and remember it so
  //    the churn doesn't retry.
  if (source.length > MAX_SOURCE_BYTES) {
    const msg = `source too large to render safely (${(source.length / 1024).toFixed(1)} KiB)`;
    failing_cache.set(cache_key, msg);
    throw create_render_error(msg);
  }

  // 5. Start the single attempt, wrapped in a best-effort deadline. The
  //    attempt promise is shared with every concurrent caller (3.) and its
  //    resolution / rejection populate the success / fail caches.
  const attempt: Promise<string> = (async () => {
    let clear_timer: () => void = () => {};
    const deadline = new Promise<never>((_unused_resolve, reject) => {
      const id = setTimeout(
        () =>
          reject(
            create_render_error(
              "render timed out; the diagram may contain a construct that hangs the renderer",
            ),
          ),
        RENDER_TIMEOUT_MS,
      );
      clear_timer = () => clearTimeout(id);
    });
    try {
      const instance = await load_mermaid();
      instance.initialize({
        startOnLoad: false,
        theme,
        securityLevel: "strict",
      });
      const work = instance.render(`enkaidu-mermaid-${++diagram_id}`, source);
      // Mark the raw render handled so a late rejection after we've already
      // timed it out doesn't surface as an unhandled promise rejection.
      work.catch(() => {});
      // The deadline only bounds *asynchronous* slowness; it cannot
      // interrupt a synchronous infinite loop (documented above).
      const { svg } = await Promise.race([work, deadline]);
      return svg;
    } catch (reason) {
      throw create_render_error(render_message(reason));
    } finally {
      clear_timer();
    }
  })();

  inflight.set(cache_key, attempt);
  attempt.then(
    (svg) => {
      inflight.delete(cache_key);
      if (rendered_cache.size >= MAX_CACHE_ENTRIES) {
        const oldest = rendered_cache.keys().next().value;
        if (oldest !== undefined) {
          rendered_cache.delete(oldest);
        }
      }
      rendered_cache.set(cache_key, svg);
    },
    (reason) => {
      inflight.delete(cache_key);
      failing_cache.set(cache_key, render_message(reason));
      // Cap the failure memo so an adversarial stream can't grow it
      // without bound; evict the oldest recorded failure.
      if (failing_cache.size > MAX_CACHE_ENTRIES * 4) {
        const oldest = failing_cache.keys().next().value;
        if (oldest !== undefined) {
          failing_cache.delete(oldest);
        }
      }
    },
  );

  return attempt;
}

// Synchronous "is it already rendered?" lookup. MermaidBlock seeds its
// initial state from this: during streaming the placeholder element (and
// the mounted component) is recreated on nearly every fragment, and
// starting already-rendered from cache means the re-creation shows the
// diagram immediately instead of flashing through the
// "Rendering diagram…" / code fallback views.
export function mermaid_cached(source: string): string | null {
  return rendered_cache.get(source + "\x00" + current_mermaid_theme()) ?? null;
}

// Symmetric to mermaid_cached: a synchronous "is this source already known
// to fail?" lookup. MermaidBlock seeds its failed/code view from this so
// a streaming re-mount of a previously-failed source skips the renderer
// entirely instead of re-attempting it — the anti-storm path.
export function mermaid_cached_error(source: string): string | null {
  const theme = current_mermaid_theme();
  const remembered = failing_cache.get(source + "\x00" + theme);
  return remembered === undefined ? null : remembered;
}