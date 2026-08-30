<script lang="ts">
  let { onask = null, loading = false } = $props();
  let text_area: HTMLTextAreaElement;
  let input_text = $state("");

  function auto_grow(e: Event) {
    let el = e.target as HTMLTextAreaElement;
    el.style.height = "auto";
    el.style.height = el.scrollHeight + "px";
    input_text = el.value;
   }

  function handle_key_event(event: KeyboardEvent) {
    if (!event.shiftKey && event.key == "Enter") {
      let textarea = event.target as HTMLTextAreaElement;
      if (textarea) {
        event.preventDefault();
        if (onask) onask(textarea.value);
        textarea.value = "";
        textarea.style.height = "auto";
        input_text = "";
        }
      }
    }

   export function focus() {
     text_area.focus();
     }
</script>

<div
  class="w-full max-w-3xl mx-auto px-3 pb-4 pt-2"
>
    <form
      class="promptbar-input group flex items-center gap-2 rounded-xl border border-base-content/15 border-l-[3px] border-l-accent/25 bg-base-200/70 px-4 py-3 shadow-sm transition-shadow focus-within:shadow-md focus-within:border-base-content/25"
       >
      <textarea
      bind:this={text_area}
      disabled={loading}
      onkeydown={handle_key_event}
      oninput={auto_grow}
      rows="1"
      class="flex-1 bg-transparent text-base-content placeholder:text-base-content/30 focus:outline-none resize-none text-base leading-relaxed"
      placeholder="Message Enkaidu…"
      ></textarea>
       <button
       type="submit"
       disabled={loading || input_text.trim() === ""}
       title="Send"
       aria-label="Send message"
       class="shrink-0 w-8 h-8 rounded-full bg-primary text-primary-content flex items-center justify-center text-sm transition-opacity disabled:opacity-30 disabled:cursor-not-allowed hover:opacity-80"
       >
         <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" class="w-4 h-4">
           <path d="M12 19V5"/>
           <path d="M5 12l7-7 7 7"/>
         </svg>
       </button>
     </form>
     <div class="text-center text-xs text-base-content/20 mt-1 group-focus-within:opacity-0 transition-opacity">
      Enter to send · Shift+Enter for newline
     </div>
</div>
