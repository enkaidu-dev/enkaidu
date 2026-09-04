<script lang="ts">
  import BlockFrame from "./BlockFrame.svelte";

  let { source, language }: { source: string; language: string } = $props();
  let view = $state<"diagram" | "code">("diagram");
</script>

<BlockFrame {language} {source} rendered={true} failed={false} bind:view>
  <div class="flex justify-center overflow-x-auto p-3">
    {@html source}
  </div>
</BlockFrame>
