// Shared prop contract for every interactive block component (the
// BlockRenderer `component` field) — used by both consumers:
// Markdown.svelte hydration (mode defaults to "inline": self-framed box)
// and the FilePanel file viewer (mode "panel": frameless bar + body that
// integrates into the panel's single-column layout).
import type { SaveOption } from "./save";

export type BlockMode = "inline" | "panel";

export interface BlockProps {
  source: string;
  // The label shown in the chrome: the fence language inline, or the full
  // file path (mono, truncated) in the panel.
  language: string;
  saves?: SaveOption[];
  saveBasename?: string;
  mode?: BlockMode;
  // Panel-mode only: wired to the panel's close affordance in the bar.
  onclose?: () => void;
}
