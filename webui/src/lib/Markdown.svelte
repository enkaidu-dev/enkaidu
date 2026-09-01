<script lang="ts">
  import { marked } from "marked";

  let { content, add_class }: { content: string; add_class?: string } =
    $props();

  // Set options
  marked.use({
    gfm: true,
  });

  function format(text: string) {
    return marked.parse(text);
  }
</script>

<div class="prose leading-[1.65] max-w-full {add_class}">
  {@html format(content)}
</div>
