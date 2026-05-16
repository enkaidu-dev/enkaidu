<script lang="ts">
  let { level }: { level: string } = $props();
</script>

{#if level == "warn"}
  <span class="badge badge-sm badge-soft badge-warning">WARN</span>
{:else if level == "success"}
  <span class="badge badge-sm badge-soft badge-success">OK</span>
{:else if level == "error"}
  <span class="badge badge-sm badge-soft badge-error">ERROR</span>
{:else if level == "info"}
  <span class="badge badge-sm badge-soft badge-info">INFO</span>
{:else}
  <span class="badge badge-sm badge-soft badge-error">{`?(${level})?`}</span>
{/if}
