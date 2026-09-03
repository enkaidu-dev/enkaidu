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
</script>

<div
  class="prose leading-[1.65] max-w-full {add_class}"
  bind:this={container}>
  {@html html}
</div>
