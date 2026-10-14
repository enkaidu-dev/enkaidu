import type { Component } from "svelte";
import type { BlockProps } from "./types";
import MermaidBlock from "./MermaidBlock.svelte";
import SvgBlock from "./SvgBlock.svelte";
import CsvBlock, { render_csv_to_html } from "./CsvBlock.svelte";
import VegaBlock from "./VegaBlock.svelte";
import MarkdownBlock from "./MarkdownBlock.svelte";
import { mermaid_cached } from "../../mermaid";
import { sanitizeSvg } from "../sanitize";
import { saveSource, saveRenderedSvg, type SaveOption } from "./save";

export interface BlockRenderer {
  language: string;
  displayName: string;
  // Every block takes the shared BlockProps contract (source, language,
  // saves, saveBasename, mode, onclose — see types.ts). Markdown.svelte
  // mounts with mode defaulting to "inline" (self-framed box); the
  // FilePanel mounts with mode "panel" (frameless bar + body).
  component: Component<BlockProps>;
  diagramLabel?: string;
  codeLabel?: string;
  getCached?(source: string): string | null;
  sniff?(source: string, lang: string): boolean;
    // Base filename stem for downloads (e.g. "diagram" -> diagram.svg,
   // diagram.mmd). Passed to the block component and used by BlockFrame.
  saveBasename?: string;
    // The save options this renderer offers; one chip each. Source-based
   // saves are always available; rendered-SVG saves appear only while the
   // <svg> renders.
  saves?: SaveOption[];
}

// Global cache for compiled Vega charts to support fluid streaming
export const vega_cache = new Map<string, string>();

// Normalize key to prevent line-ending (\r\n vs \n) and trailing whitespace mismatches
export function normalize_cache_key(source: string): string {
  return source.replace(/\r\n/g, "\n").trim();
}

// --- Shared anti-lockup backstops -----------------------------------------
//
// The "storm on error" class was first seen with mermaid and fixed there
// (2026-10-14): `Markdown.svelte` re-runs `render_markdown` and wholesale
// replaces the `@html` on every streamed fragment, so every block placeholder
// is unmounted and re-mounted (after a 150 ms debounce). Any per-block heavy
// render on mount therefore re-runs on each gap. The model that kills the
// storm is to record a render's result *or its failure* in a per-source memo,
// so a re-mount short-circuits and the heavy work runs at most ONCE per
// source. Vega is the one other renderer whose main-thread render is both
// heavy and failure-storm-capable, so it gets the same treatment; csv/svg get
// the cheaper "memoize the placeholder producer" treatment (they can't storm
// on error, only on valid-but-large input).
//
// A source-size backstop refuses a pathologically large input before the
// renderer sees it (stops an exponential layout / parse). And a best-effort
// deadline bounds an *asynchronous* slow render; it cannot interrupt a
// *synchronous* CPU burst on the main thread (the same documented gap noted
// in mermaid.ts — a true small-input hang is the one case that still needs a
// Web Worker, which is deferred).

// Refuse sources larger than this outright.
export const MAX_SOURCE_BYTES = 256 * 1024;

// Best-effort deadline for a single (asynchronous) render.
export const RENDER_TIMEOUT_MS = 10000;

// The message a single render attempt times out with — shared by callers so
// the "Couldn't render" strip reads consistently across renderers.
export const RENDER_TIMEOUT_MESSAGE =
  "render timed out; the source may contain a construct that hangs the renderer";

// Vega failure memo, keyed like the success cache (`vega_cache`, source-only —
// see the theme-keying note on vega_cache in the VegaBlock component). The
// success side is already memoized; this records *failures* so re-mounts don't
// re-embed a known-bad spec. Capped so an adversarial stream can't grow it.
const vega_fail = new Map<string, string>();
const VEGA_FAIL_CAP = 200;

// Record a vega render failure for `source` (normalizes the key).
export function record_vega_failure(source: string, message: string): void {
  vega_fail.set(normalize_cache_key(source), message);
  if (vega_fail.size > VEGA_FAIL_CAP) {
    const oldest = vega_fail.keys().next().value;
    if (oldest !== undefined) {
      vega_fail.delete(oldest);
    }
  }
}

// Synchronous "is this source already known to fail to render?" lookup — the
// seed VegaBlock uses so a re-mount of a known-bad spec shows its recorded
// "Couldn't render" view instantly instead of re-embedding.
export function vega_cached_error(source: string): string | null {
  return vega_fail.get(normalize_cache_key(source)) ?? null;
}

// Placeholder producer memo. Each `getCached()` that builds a non-trivial
// string runs on *every* streamed fragment (see the header above); memoizing
// by normalized source turns that per-fragment work into a Map lookup after
// the first. Used by the csv and svg renderers.
const csv_placeholder_cache = new Map<string, string>();
const svg_placeholder_cache = new Map<string, string>();

function memo_cached(
  cache: Map<string, string>,
  source: string,
  produce: () => string,
): string {
  const key = normalize_cache_key(source);
  let hit = cache.get(key);
  if (hit === undefined) {
    hit = produce();
    cache.set(key, hit);
  }
  return hit;
}

// Shared renderer config for the markdown block; both `markdown` and `md`
// fence languages point at it so they resolve identically. Markdown is
// explicit-language only (no content sniffing — nearly anything looks like
// markdown, so sniffing would hijack shell/python/csv fences).
const markdownRenderer: BlockRenderer = {
  language: "markdown",
  displayName: "markdown",
  component: MarkdownBlock,
  diagramLabel: "Preview",
  codeLabel: "Source",
  saveBasename: "note",
  saves: [saveSource("Source", "md")],
};

const registry: Record<string, BlockRenderer> = {
  mermaid: {
    language: "mermaid",
    displayName: "mermaid",
    component: MermaidBlock,
    diagramLabel: "Diagram",
    codeLabel: "Code",
    getCached: mermaid_cached,
    saveBasename: "diagram",
    saves: [saveSource("Source", "mmd"), saveRenderedSvg("SVG", "svg")],
    },
  svg: {
    language: "svg",
    displayName: "svg",
    component: SvgBlock,
    diagramLabel: "Diagram",
    codeLabel: "Source",
      // Defense in depth: sanitize the cached (placeholder) path too, so
     // even if render_markdown's DOMPurify pass is ever bypassed, the
     // SVG content is already clean. Memoized so a large valid svg isn't
     // re-sanitized on every streamed fragment.
    getCached: (source: string) =>
      memo_cached(svg_placeholder_cache, source, () => sanitizeSvg(source)),
    saveBasename: "picture",
    saves: [saveSource("SVG", "svg")],
    sniff(source: string, lang: string): boolean {
      const normalizedLang = lang.toLowerCase();
      if (
        normalizedLang === "" ||
        normalizedLang === "xml" ||
        normalizedLang === "html" ||
        normalizedLang === "plaintext"
        ) {
        const trimmed = source.trim();
        return /^(?:<\?xml[^>]*\?>\s*)?(?:<!--[\s\S]*?-->\s*)*<svg[\s\S]*<\/svg>$/i.test(trimmed);
        }
      return false;
      },
    },
  csv: {
    language: "csv",
    displayName: "csv table",
    component: CsvBlock,
    diagramLabel: "Table",
    codeLabel: "Raw",
    // Memoized so a valid-but-large csv isn't re-parsed/re-rendered to a fresh
    // string on every streamed fragment (the producer runs on each fragment).
    getCached: (source: string) =>
      memo_cached(csv_placeholder_cache, source, () => render_csv_to_html(source)),
    saveBasename: "table",
    saves: [saveSource("CSV", "csv")],
    sniff(source: string, lang: string): boolean {
      const normalizedLang = lang.toLowerCase();
      if (normalizedLang === "" || normalizedLang === "plaintext") {
        const trimmed = source.trim();
        if (trimmed === "") return false;

          // A robust heuristic to sniff CSV:
         // Has at least two lines, and the count of unquoted commas per line
         // is exactly consistent across the first 3 lines.
        const lines = trimmed.split(/\r?\n/).filter(line => line.trim() !== "");
        if (lines.length < 2) return false;

        const counts = lines.slice(0, 3).map(line => {
          let count = 0;
          let insideQuotes = false;
          for (let i = 0; i < line.length; i++) {
            if (line[i] === '"') insideQuotes = !insideQuotes;
            else if (line[i] === ',' && !insideQuotes) count++;
            }
          return count;
          });

        const firstCount = counts[0];
        if (firstCount === 0) return false;
        return counts.every(c => c === firstCount);
        }
      return false;
      },
    },
   "vega-lite": {
    language: "vega-lite",
    displayName: "chart",
    component: VegaBlock,
    diagramLabel: "Chart",
    codeLabel: "JSON",
    getCached: (source: string) => vega_cache.get(normalize_cache_key(source)) ?? null,
    sniff: sniff_vega,
    saveBasename: "chart",
    saves: [saveSource("JSON", "json"), saveRenderedSvg("SVG", "svg")],
    },
  vega: {
    language: "vega",
    displayName: "chart",
    component: VegaBlock,
    diagramLabel: "Chart",
    codeLabel: "JSON",
    getCached: (source: string) => vega_cache.get(normalize_cache_key(source)) ?? null,
    sniff: sniff_vega,
    saveBasename: "chart",
    saves: [saveSource("JSON", "json"), saveRenderedSvg("SVG", "svg")],
    },
  markdown: markdownRenderer,
  md: markdownRenderer,
};

// Dedicated sniffer function for Vega / Vega-Lite JSON structures
function sniff_vega(source: string, lang: string): boolean {
  const normalizedLang = lang.toLowerCase();

    // Only sniff if the declared block is generic JSON, unannotated, or plain text
  if (
    normalizedLang === "" ||
    normalizedLang === "json" ||
    normalizedLang === "plaintext"
    ) {
    try {
      const parsed = JSON.parse(source);

        // Ensure it's a non-null object
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
          // Heuristic 1: Explicit Vega schema declaration
        if (typeof parsed.$schema === "string" && parsed.$schema.includes("vega")) {
          return true;
          }

          // Heuristic 2: Coexistence of core visualization grammar keys
        const hasData = "data" in parsed;
        const hasVisuals =
            "mark" in parsed ||
            "layer" in parsed ||
            "hconcat" in parsed ||
            "vconcat" in parsed;

        if (hasData && hasVisuals) {
          return true;
          }
       }
     } catch {
        // Not valid JSON, ignore and let standard rendering handle it
      }
    }
  return false;
}

export function get_renderer(lang: string): BlockRenderer | undefined {
  return registry[lang.toLowerCase()];
}

export function is_registered_renderer(lang: string): boolean {
  return lang.toLowerCase() in registry;
}

// Resolve a viewed file to its block renderer, keyed by file extension.
// Used by FilePanel so files of these types render with the same
// interactive blocks (view toggle + save chips) as inline fences.
// `json` is the deliberate exception: only files that actually sniff as
// a Vega/Vega-Lite spec become blocks; plain JSON stays raw highlighted
// text. Anything else resolves to undefined (raw-highlighted fallback).
export function file_renderer(
  path: string,
  source: string,
): BlockRenderer | undefined {
  const name = path.split("/").filter(Boolean).pop() ?? "";
  const dot = name.lastIndexOf(".");
  if (dot < 0) return undefined;
  const ext = name.slice(dot + 1).toLowerCase();

  switch (ext) {
    case "mmd":
    case "mermaid":
      return get_renderer("mermaid");
    case "svg":
      return get_renderer("svg");
    case "csv":
      return get_renderer("csv");
    case "md":
    case "markdown":
      return get_renderer("markdown");
    case "json":
      // sniff_renderer only matches the vega renderers when the content
      // really carries a vega/$schema or data+mark shape.
      return sniff_renderer("json", source);
    default:
      return undefined;
  }
}

export function sniff_renderer(lang: string, source: string): BlockRenderer | undefined {
  const normalizedLang = lang.toLowerCase();

  if (is_registered_renderer(normalizedLang)) {
    return get_renderer(normalizedLang);
    }

  for (const key of Object.keys(registry)) {
    const renderer = registry[key];
    if (renderer.sniff?.(source, normalizedLang)) {
      return renderer;
      }
    }

  return undefined;
}
