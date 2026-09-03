<script lang="ts">
  import { render_markdown } from "../markdown";

  let { content, add_class }: { content: string; add_class?: string } =
    $props();

  // Memoized: re-parses only when `content` actually changes, not on
  // every re-render of the card.
  let html = $derived(render_markdown(content));
</script>

<div class="prose leading-[1.65] max-w-full {add_class}">
  {@html html}
</div>
