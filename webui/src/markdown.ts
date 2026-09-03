// Shared, one-time marked configuration.
// A JS module is evaluated exactly once per app load, so calling
// marked.use() here (instead of inside a Svelte component's script setup,
// which runs on EVERY instantiation) keeps the highlight extension
// registered exactly once. Duplicating it via per-component marked.use()
// calls makes parsing recursively re-enter and grows exponentially with
// the number of rendered Markdown components.
import { marked } from "marked";
import { markedHighlight } from "marked-highlight";
import hljs from "highlight.js/lib/common";

marked.use(
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
