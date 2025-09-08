<script lang="ts">
  let { onask = null } = $props();

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
</script>

<div
  class="w-full bg-base-200 px-10 py-5 fixed bottom-0 border-t-2 border-base-content"
>
  <form>
    <fieldset class="fieldset">
      <textarea
        onkeydown={handle_key_event}
        class="textarea h-20 w-full"
        placeholder="Prompt"
      ></textarea>
      <div class="label">
        Press ENTER to submit the query; use Shift-ENTER to create new lines.
      </div>
    </fieldset>
  </form>
</div>
