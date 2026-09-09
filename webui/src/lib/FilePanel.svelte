<script lang="ts">
  let {
    path,
    body,
    loading = false,
    error = "",
    onclose,
  }: {
    path: string;
    body: string;
    loading?: boolean;
    error?: string;
    onclose?: () => void;
  } = $props();

  function file_name() {
    const parts = path.split("/").filter(Boolean);
    return parts.length > 0 ? parts[parts.length - 1] : path;
  }
</script>

<aside
  class="h-full w-1/2 min-w-[20rem] max-w-2xl flex flex-col overflow-hidden border-l border-base bg-base-100 md:max-w-3xl"
>
  <div
    class="flex items-center gap-2 border-b border-base bg-base-200 px-3 py-2"
  >
    <span class="min-w-0 flex-1 truncate font-mono text-xs" title={path}>
      {path}
    </span>
    <button
      type="button"
      class="action-chip"
      onclick={() => onclose?.()}
      title="Close panel"
      aria-label="Close panel"
    >
      ✕
    </button>
  </div>

  <div class="min-h-0 flex-1 overflow-auto">
    {#if loading}
      <p class="p-3 text-sm text-base-content/50">
        Loading {file_name()}…
      </p>
    {:else if error}
      <p class="m-3 rounded-md border-l-[3px] border-error/70 bg-error/8 p-2 text-sm text-base-content/80"
        >{error}</p
      >
    {:else}
      <pre
        class="whitespace-pre-wrap break-words p-3 font-mono text-xs leading-5 text-base-content/90"
        >{body}</pre
      >
    {/if}
  </div>
</aside>
