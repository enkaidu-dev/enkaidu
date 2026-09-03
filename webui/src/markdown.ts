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

// Fenced code blocks get wrapped in a container with a "Copy" button
// (revealed on hover; Markdown.svelte owns the click via one delegated
// listener, since {@html} replaces the block DOM on every content
// change). The <pre> below is emitted here rather than by marked,
// because marked's renderer patching offers no way to call the
// previously-registered code renderer — and markedHighlight's walkTokens
// pass has already replaced token.text with the highlight.js HTML
// (escaped=true) before the renderer runs, so the tokens carry
// everything we need.
//
// Only fenced code goes through renderer.code (inline code uses
// renderer.codespan), and the <template>-bearing mermaid placeholders
// are a separate extension, so neither is affected.
function escape_html(text: string, encode: boolean): string {
  const replacements: Record<string, string> = {
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  };
  const pattern = encode
    ? /[&<>"']/g
    : /[<>"']|&(?!(#?\d+|#?[Xx][A-Fa-f0-9]+|\w+);)/g;
  return text.replace(pattern, (ch) => replacements[ch] ?? ch);
}

function render_copyable_code(
  code: unknown,
  infoString: unknown,
  escaped: unknown,
): string {
  // Renderer methods are called either as (text, lang, escaped) or with
  // the token object as a single argument, depending on the marked
  // version — handle both, like marked-highlight itself does.
  let text: string;
  let lang: string;
  let is_escaped: boolean;
  if (typeof code === "string") {
    text = code;
    lang = String(infoString ?? "");
    is_escaped = escaped === true;
  } else {
    const token = (code ?? {}) as {
      text?: string;
      lang?: string;
      escaped?: boolean;
    };
    text = token.text ?? "";
    lang = token.lang ?? "";
    is_escaped = token.escaped === true;
  }
  const language = lang.match(/\S*/)?.[0] ?? "";
  const class_attr = language
    ? ` class="hljs language-${language.replace(/["&<>]/g, "")}"`
    : "";
  text = text.replace(/\n$/, "");
  const inner = is_escaped ? text : escape_html(text, true);
  return (
    '<div class="enkaidu-code group/code relative">' +
    '<button type="button" data-copy-code aria-label="Copy code" ' +
    'class="enkaidu-copy absolute right-2 top-2 z-10 opacity-0 transition-opacity duration-150 group-hover/code:opacity-100 focus-visible:opacity-100">' +
    "Copy</button>" +
    `<pre><code${class_attr}>${inner}\n</code></pre>` +
    "</div>"
  );
}

// Registration order matters: marked's use() calls the LAST registered
// renderer first (earlier ones are only reached when a later one returns
// false, which the <pre> producer below never does). So the copy wrapper
// is registered AFTER markedHighlight to take precedence over the plain
// <pre> it would otherwise emit.
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
  {
    renderer: {
      code(code?: unknown, infoString?: unknown, escaped?: unknown) {
        return render_copyable_code(code, infoString, escaped);
      },
    },
  },
);

export function render_markdown(text: string): string {
  return marked.parse(text) as string;
}