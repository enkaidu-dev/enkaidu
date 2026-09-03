// Shared, one-time marked configuration.
// A JS module is evaluated exactly once per app load, so calling
// marked.use() here (instead of inside a Svelte component's script setup,
// which runs on EVERY instantiation) keeps the extension registrations
// exactly once. Duplicating them via per-component marked.use()
// calls makes parsing recursively re-enter and grows exponentially with
// the number of rendered Markdown components.
import { marked } from "marked";
import { markedHighlight } from "marked-highlight";
import hljs from "highlight.js/lib/common";

// ```mermaid fences become a placeholder block that Markdown.svelte
// hydrates into an interactive MermaidBlock (rendered diagram with a
// Diagram/Code toggle). The diagram source is kept HTML-escaped inside
// a <template>; Markdown.svelte reads it out when it mounts the block
// component, so nothing executes at parse time.
function render_mermaid_placeholder(source: string): string {
  const escaped = source
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
  // Also render the diagram source as a visible code fallback. The
  // placeholder is inert — Markdown.svelte hydrates it into the
  // interactive MermaidBlock and replaces these children — so without
  // the fallback, the moment a streaming fence closes there is a
  // window where the block renders nothing (until hydration runs and
  // mermaid itself renders, which can take a while on first load).
  // Showing the source keeps the block stable visually, degrades
  // gracefully if hydration fails, and matches the "Code" view of
  // the interactive block.
  const fallback = hljs.highlight(source, { language: "plaintext" }).value;
  return (
    '<div class="enkaidu-codeblock enkaidu-codeblock-mermaid">' +
    `<template>${escaped}</template>` +
    '<pre class="not-prose overflow-x-auto bg-base-100/50 p-3 font-mono text-xs leading-relaxed"><code>' +
    fallback +
    "</code></pre>" +
    "</div>"
  );
}

marked.use(
  {
    extensions: [
      {
        name: "mermaid",
        level: "block",
        start(src) {
          const index = src.indexOf("```mermaid");
          if (index < 0) return undefined;
          if (index > 0 && src[index - 1] !== "\n") return undefined;
          return index;
        },
        tokenizer(src) {
          const open = /^```mermaid[ \t]*\r?\n/.exec(src);
          if (!open) return undefined;
          const body_start = open[0].length;
          const close = src.indexOf("```", body_start);
          if (close < 0) {
            // Fence not closed yet (still streaming) — let the default
            // code-fence rules render it as a regular code block.
            return undefined;
          }
          // The closing fence must be alone on its line.
          if (!/^[ \t]*(\r?\n|$)/.test(src.slice(close + 3))) return undefined;
          const source = src.slice(body_start, close).replace(/\r?\n$/, "");
          if (source.trim() === "") return undefined;
          return {
            type: "mermaid",
            raw: src.slice(0, close + 3),
            source,
          };
        },
        renderer(token) {
          return render_mermaid_placeholder((token as { source?: string })?.source ?? "");
        },
      },
    ],
  },
  markedHighlight({
    langPrefix: "hljs language-",
    highlight(code, lang) {
      const language = hljs.getLanguage(lang) ? lang : "plaintext";
      return hljs.highlight(code, { language }).value;
    },
  }),
);

export function render_markdown(text: string): string {
  return marked.parse(text) as string;
}