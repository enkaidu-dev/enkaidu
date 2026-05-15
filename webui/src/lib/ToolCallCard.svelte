<script lang="ts">
  import Markdown from "./Markdown.svelte";

  let { name, args }: { name: string; args: string } = $props();
  let params = JSON.parse(args);
</script>

<div
  class="px-4 place-self-start bg-base-100 text-sm text-success"
  // class=" w-7/8 px-4 py-1 card card-xs shadow-sm place-self-start bg-base-100 text-sm text-base-content dark:border-base-content dark:border-1 dark:border-dashed"
>
  <div class="card-title text-ghost text-xs">
    <i>
      {#if params.reason}
        {params.reason} → CALL <code>{name}</code>
      {:else}
        → CALL <code>{name}</code> with <code>{args}</code>
      {/if}
    </i>
  </div>
</div>
