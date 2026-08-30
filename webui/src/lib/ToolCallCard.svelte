<script lang="ts">
  let { name, args }: { name: string; args: string } = $props();

   // svelte-ignore state_referenced_locally
  let params = JSON.parse(args);
</script>

<div
  class="place-self-start w-7/8 text-xs text-base-content/40 font-mono"
>
      {#if params.reason}
        <span>{params.reason} → </span><span class="text-base-content/55">{name}</span>
      {:else}
        <span>→ </span><span class="text-base-content/55">{name}</span>
        <span class="text-base-content/30"> ({args})</span>
      {/if}
</div>
