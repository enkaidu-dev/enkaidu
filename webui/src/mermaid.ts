// Lazy one-time mermaid load + render helper with a small result cache.
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

let diagram_id = 0;

// mermaid only ships fixed single-scheme themes; we follow the OS
// setting so diagrams sit well in both app themes. "neutral" and "dark"
// are chosen because they are the low-chroma, gray-based pair that
// matches the app's warm palette better than the stock "default/forest".
function current_mermaid_theme(): string {
  return window.matchMedia("(prefers-color-scheme: dark)").matches
    ? "dark"
    : "neutral";
}

export async function mermaid_render(source: string): Promise<string> {
  const theme = current_mermaid_theme();
  const cache_key = source + "\x00" + theme;
  const cached = rendered_cache.get(cache_key);
  if (cached !== undefined) {
    return cached;
  }
  const instance = await load_mermaid();
  instance.initialize({
    startOnLoad: false,
    theme,
    securityLevel: "strict",
  });
  const { svg } = await instance.render(`enkaidu-mermaid-${++diagram_id}`, source);
  if (rendered_cache.size >= MAX_CACHE_ENTRIES) {
    const oldest = rendered_cache.keys().next().value;
    if (oldest !== undefined) {
      rendered_cache.delete(oldest);
    }
  }
  rendered_cache.set(cache_key, svg);
  return svg;
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