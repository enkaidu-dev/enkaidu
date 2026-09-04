import type { Component } from "svelte";
import MermaidBlock from "./MermaidBlock.svelte";
import SvgBlock from "./SvgBlock.svelte";
import { mermaid_cached } from "../../mermaid";

export interface BlockRenderer {
  language: string;
  displayName: string;
  component: Component<{ source: string; language: string }>;
  getCached?(source: string): string | null;
  sniff?(source: string, lang: string): boolean; // Dynamic content checking
}

const registry: Record<string, BlockRenderer> = {
  mermaid: {
    language: "mermaid",
    displayName: "mermaid",
    component: MermaidBlock,
    getCached: mermaid_cached,
  },
  svg: {
    language: "svg",
    displayName: "svg",
    component: SvgBlock,
    getCached: (source: string) => source,
    sniff(source: string, lang: string): boolean {
      const normalizedLang = lang.toLowerCase();
      // Sniff if the declared language is missing or a generic markup/text wrapper
      if (
        normalizedLang === "" ||
        normalizedLang === "xml" ||
        normalizedLang === "html" ||
        normalizedLang === "plaintext"
      ) {
        const trimmed = source.trim();
        // Matches optional XML prologue, optional comments, and a root <svg> element
        return /^(?:<\?xml[^>]*\?>\s*)?(?:<!--[\s\S]*?-->\s*)*<svg[\s\S]*<\/svg>$/i.test(trimmed);
      }
      return false;
    },
  },
};

export function get_renderer(lang: string): BlockRenderer | undefined {
  return registry[lang.toLowerCase()];
}

export function is_registered_renderer(lang: string): boolean {
  return lang.toLowerCase() in registry;
}

/**
 * Resolves the appropriate block renderer, either by an explicit language match
 * or by executing sniff rules registered on any block renderer.
 */
export function sniff_renderer(lang: string, source: string): BlockRenderer | undefined {
  const normalizedLang = lang.toLowerCase();

  // 1. Direct match: If the language is explicitly registered, use it.
  if (is_registered_renderer(normalizedLang)) {
    return get_renderer(normalizedLang);
  }

  // 2. Sniff match: Check each registered renderer to see if it claims the content.
  for (const key of Object.keys(registry)) {
    const renderer = registry[key];
    if (renderer.sniff?.(source, normalizedLang)) {
      return renderer;
    }
  }

  return undefined;
}
