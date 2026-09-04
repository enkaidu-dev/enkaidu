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
import { get_renderer, sniff_renderer } from "./lib/blocks/registry";

// Custom code blocks become placeholder blocks that Markdown.svelte
// hydrates into interactive components (e.g. MermaidBlock). The source
// is kept HTML-escaped inside a <template>; Markdown.svelte reads it out
// when it mounts the block component, so nothing executes at parse time.
function render_block_placeholder(lang: string, source: string): string {
  const escaped = source
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
  // Visible content while the placeholder is inert. Two cases:
  //
  // 1. Cache hit — a rendered representation for this source already exists
  //    (the diagram/graphic was rendered once and its surrounding markdown keeps
  //    re-parsing as the rest of the response streams). Emit a pixel
  //    clone of BlockFrame's Diagram view (same frame, header and
  //    chips) around the cached content. The markup deliberately duplicates
  //    BlockFrame.svelte's Diagram view. With both the
  //    placeholder and the hydrated block indistinguishable, the
  //    placeholder → block swap during stream churn produces no visible
  //    flash at all.
  //
  // 2. Cache miss — first render (or the source just changed).
  //    Show the source as highlighted plaintext: nothing else is
  //    available yet, and it matches the block's "Code" view.
  const renderer = get_renderer(lang);
  const cached_content = renderer?.getCached?.(source);
  const displayName = renderer?.displayName ?? lang;
  const diagramLabel = renderer?.diagramLabel ?? "Diagram";
  const codeLabel = renderer?.codeLabel ?? "Source";

  const visible = cached_content
    ? (
        '<div class="not-prose my-6 w-full overflow-hidden rounded-lg border border-base/85 text-sm">' +
        '<div class="flex items-center justify-between gap-2 border-b border-base/85 bg-base-200 px-3 py-1.5">' +
        `<span class="font-mono text-xs text-base-content/50">${displayName}</span>` +
        '<div class="flex items-center gap-1">' +
        `<span class="action-chip active">${diagramLabel}</span>` +
        `<span class="action-chip">${codeLabel}</span>` +
        "</div></div>" +
        `<div class="flex justify-center overflow-x-auto p-3">${cached_content}</div>` +
        "</div>"
      )
    : (
        '<pre class="not-prose overflow-x-auto bg-base-100/50 p-3 font-mono text-xs leading-relaxed"><code>' +
        hljs.highlight(source, { language: "plaintext" }).value +
        "</code></pre>"
      );
  return (
    `<div class="enkaidu-codeblock" data-language="${lang}">` +
    `<template>${escaped}</template>` +
    visible +
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
// renderer.codespan), and the <template>-bearing custom placeholders
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
    ? /[&<> "']/g
    : /[<> "']|&(?!(#?\d+|#?[Xx][A-Fa-f0-9]+|\w+);)/g;
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
// renderer first. So the copy wrapper is registered AFTER markedHighlight
// to take precedence over the plain <pre> it would otherwise emit.
marked.use(
  {
    extensions: [
      {
        name: "custom-block",
        level: "block",
        start(src) {
          const index = src.indexOf("```");
          if (index < 0) return undefined;
          if (index > 0 && src[index - 1] !== "\n") return undefined;
          return index;
        },
        tokenizer(src) {
          // Match any backtick block fence, allowing empty/missing language
          const match = /^```([a-zA-Z0-9_-]*)[ \t]*\r?\n/.exec(src);
          if (!match) return undefined;
          
          const rawLang = match[1];

          const body_start = match[0].length;
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

          // Attempt to resolve or sniff the appropriate block renderer
          const renderer = sniff_renderer(rawLang, source);
          if (!renderer) return undefined;

          return {
            type: "custom-block",
            raw: src.slice(0, close + 3),
            lang: renderer.language,
            source,
          };
        },
        renderer(token) {
          const t = token as unknown as { lang: string; source: string };
          return render_block_placeholder(t.lang, t.source);
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
