<script lang="ts">
  import { onDestroy, mount, unmount } from "svelte";
  import { render_markdown } from "../markdown";
  import MermaidBlock from "./MermaidBlock.svelte";

  let {content, add_class}: {content: string; add_class?: string} = $props();

  // Memoized: re-parses only when `content` actually changes, not on
  // every re-render of the card.
  let html = $derived(render_markdown(content));

  // Hydration for interactive code blocks (currently mermaid): the
  // marked extension emits inert placeholders (.enkaidu-codeblock)
  // whose source lives in a <template>. When the rendered HTML
  // settles, we mount a MermaidBlock component into each placeholder.
  //
  // The @html string is replaced wholesale on every content change
  // (streaming fragments), so placeholders — and their components —
  // are recreated too. We track instances by their placeholder element
  // and destroy the ones whose element is gone; mounting happens
  // debounced so a mid-stream burst doesn't churn instances.
  let container = $state<HTMLDivElement | null>(null);
  // Svelte 5 imperative mount API: components are plain functions now, so
  // `new Component({target})` / `instance.destroy()` don't work — use
  // mount()/unmount() from 'svelte'.
  const instances = new Map<Element, Record<string, unknown>>();
  let hydrate_timer: ReturnType<typeof setTimeout> | undefined;

  function hydrate_blocks() {
    hydrate_timer = undefined;
    const live = new Set<Element>();
    container?.querySelectorAll(".enkaidu-codeblock").forEach((el) =>
      live.add(el),
    );

    for (const [el, instance] of instances) {
      if (!live.has(el)) {
        try {
          unmount(instance);
        } catch (error) {
          console.error("Failed to unmount mermaid block", error);
        }
        instances.delete(el);
      }
    }

    for (const el of live) {
      if (instances.has(el)) continue;
      const template = el.querySelector("template");
      const source = template?.content.textContent ?? "";
      // Clear the placeholder children (template + visible code fallback)
      // so the interactive block renders by itself.
      el.replaceChildren();
      try {
        const instance = mount(MermaidBlock, {
          target: el,
          props: {source},
        });
        instances.set(el, instance);
      } catch (error) {
        console.error("Failed to mount mermaid block", error);
      }
    }
  }

  $effect(() => {
    void html; // re-run whenever the rendered HTML changes
    if (hydrate_timer !== undefined) {
      clearTimeout(hydrate_timer);
    }
    hydrate_timer = setTimeout(hydrate_blocks, 150);
  });

  onDestroy(() => {
    if (hydrate_timer !== undefined) clearTimeout(hydrate_timer);
    instances.forEach((instance) => unmount(instance));
    instances.clear();
  });

  // Copy buttons for code blocks. The {@html} string is wholesale
  // replaced on every content change, so instead of wiring each button
  // individually we keep ONE delegated listener on the persistent
  // container div: it survives every re-render and reaches whatever
  // block is on screen.
  const flash_timers = new WeakMap<Element, number>();

  async function copy_to_clipboard(text: string): Promise<boolean> {
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

  function flash_copied(chip: Element): void {
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

  function handle_copy_click(event: MouseEvent): void {
    const target = event.target;
    if (!(target instanceof Element)) return;
    const chip = target.closest("[data-copy-code]");
    if (!chip) return;
    const pre = chip.closest(".enkaidu-code")?.querySelector("pre");
    if (!pre) return;
    // The highlighted spans don't change the text content, so the
    // pre's textContent IS the original fenced code.
    void copy_to_clipboard((pre.textContent ?? "").replace(/\n$/, "")).then(
      (ok) => {
        if (ok) flash_copied(chip);
      },
    );
  }

  $effect(() => {
    const el = container;
    if (!el) return;
    el.addEventListener("click", handle_copy_click);
    return () => el.removeEventListener("click", handle_copy_click);
  });
</script>

<div
  class="prose leading-[1.65] max-w-full {add_class}"
  bind:this={container}>
  {@html html}
</div>
