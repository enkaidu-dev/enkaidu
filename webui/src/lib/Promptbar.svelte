<script lang="ts">
  let { onask = null, loading = false } = $props();
  let text_area: HTMLTextAreaElement;

  function handle_key_event(event: KeyboardEvent) {
    if (!event.shiftKey && event.key == "Enter") {
      let textarea = event.target as HTMLTextAreaElement;
      if (textarea) {
        event.preventDefault(); // don't process Enter
        if (onask) onask(textarea.value);
        // clear and block
        textarea.value = "";
      }
    }
  }

  export function focus() {
    text_area.focus();
  }
</script>

<div
  class="relative w-full bg-base-200 px-10 py-5 bottom-0 border-t-2 border-base-content"
>
  <form class={loading ? " blur-xs " : ""}>
    <fieldset class="fieldset">
      <textarea
        bind:this={text_area}
        disabled={loading}
        onkeydown={handle_key_event}
        class="textarea h-20 w-full mx-auto max-w-5xl dark:border-3"
        placeholder="Prompt"
      ></textarea>
      <div class="label mx-auto">
        Press ENTER to submit the query; use Shift-ENTER to create new lines.
      </div>
    </fieldset>
  </form>
  {#if loading}
    <div
      class="absolute inset-0 w-full h-full flex items-center place-content-center"
    >
      <span class="loading loading-spinner text-primary loading-xl"></span>
    </div>
  {/if}
</div>
