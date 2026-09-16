// Shared copy-chip machinery for rendered code views. Markdown.svelte and
// FilePanel.svelte each wire ONE delegated click listener on their own
// persistent container and hand events to handle_copy_click: the inner
// markup ({@html} or imperative re-mounts) is replaced wholesale, so
// per-chip listeners can never survive — a listener on the stable
// container can.
//
// Extracted from Markdown.svelte so the file panel's rendered sources get
// the identical Copy affordance (copy raw text, flash "Copied" for 1200 ms).

const flash_timers = new WeakMap<Element, number>();

export async function copy_to_clipboard(text: string): Promise<boolean> {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    // Fallback for non-secure contexts (the app is often served on
    // plain HTTP, where navigator.clipboard is unavailable).
    try {
      const ta = document.createElement("textarea");
      ta.value = text;
      ta.style.position = "fixed";
      ta.style.opacity = "0";
      document.body.appendChild(ta);
      ta.select();
      const ok = document.execCommand("copy");
      ta.remove();
      return ok;
    } catch {
      return false;
    }
  }
}

export function flash_copied(chip: Element): void {
  const existing = flash_timers.get(chip);
  if (existing !== undefined) window.clearTimeout(existing);
  if (!chip.hasAttribute("data-copy-label")) {
    chip.setAttribute("data-copy-label", chip.textContent ?? "");
  }
  chip.textContent = "Copied";
  const timer = window.setTimeout(() => {
    chip.textContent = chip.getAttribute("data-copy-label") ?? "";
    flash_timers.delete(chip);
  }, 1200);
  flash_timers.set(chip, timer);
}

export function handle_copy_click(event: MouseEvent): void {
  const target = event.target;
  if (!(target instanceof Element)) return;
  const chip = target.closest("[data-copy-code]");
  if (!chip) return;
  const pre = chip.closest(".enkaidu-code")?.querySelector("pre");
  if (!pre) return;
  // The highlighted spans don't change the text content, so the
  // <pre>'s textContent IS the original code.
  void copy_to_clipboard((pre.textContent ?? "").replace(/\n$/, "")).then(
    (ok) => {
      if (ok) flash_copied(chip);
    },
  );
}
