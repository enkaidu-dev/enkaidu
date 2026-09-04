import type { Component } from "svelte";
import MermaidBlock from "./MermaidBlock.svelte";
import SvgBlock from "./SvgBlock.svelte";
import CsvBlock, { render_csv_to_html } from "./CsvBlock.svelte";
import VegaBlock from "./VegaBlock.svelte";
import { mermaid_cached } from "../../mermaid";

export interface BlockRenderer {
  language: string;
  displayName: string;
  component: Component<{ source: string; language: string }>;
  diagramLabel?: string;
  codeLabel?: string;
  getCached?(source: string): string | null;
  sniff?(source: string, lang: string): boolean;
}

// Global cache for compiled Vega charts to support fluid streaming
export const vega_cache = new Map<string, string>();

// Normalize key to prevent line-ending (\r\n vs \n) and trailing whitespace mismatches
export function normalize_cache_key(source: string): string {
  return source.replace(/\r\n/g, "\n").trim();
}

const registry: Record<string, BlockRenderer> = {
  mermaid: {
    language: "mermaid",
    displayName: "mermaid",
    component: MermaidBlock,
    diagramLabel: "Diagram",
    codeLabel: "Code",
    getCached: mermaid_cached,
  },
  svg: {
    language: "svg",
    displayName: "svg",
    component: SvgBlock,
    diagramLabel: "Diagram",
    codeLabel: "Source",
    getCached: (source: string) => source,
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
    getCached: render_csv_to_html,
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
  },
  vega: {
    language: "vega",
    displayName: "chart",
    component: VegaBlock,
    diagramLabel: "Chart",
    codeLabel: "JSON",
    getCached: (source: string) => vega_cache.get(normalize_cache_key(source)) ?? null,
    sniff: sniff_vega,
  },
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
