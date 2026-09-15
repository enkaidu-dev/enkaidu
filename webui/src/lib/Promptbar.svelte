<script lang="ts">
  import { PromptHistory } from "./prompt_history";

  let { onask = null, loading = false } = $props();
  let text_area = $state<HTMLTextAreaElement | undefined>(undefined);
  let input_text = $state("");
  let root_el = $state<HTMLDivElement | null>(null);

  const history = new PromptHistory({ maxSize: 200 });

  // Load history from server once on mount
  $effect(() => {
    history.loadFromServer();
  });

  // Publish this bar's live height to CSS as `--promptbar-h` (on <html>), so
  // the scrollable-content height caps in app.css (--scrollable-max-h, used
  // by .prose pre and the markdown preview body) reserve the space below
  // this bottom-pinned bar. A ResizeObserver catches every way the bar's
  // height changes: window resize, textarea auto-grow, the session tab
  // appearing, and the hint line toggling on focus.
  $effect(() => {
    const el = root_el;
    if (!el) return;
    const set_h = () =>
      document.documentElement.style.setProperty(
        "--promptbar-h",
        el.offsetHeight + "px",
      );
    set_h();
    const ro = new ResizeObserver(set_h);
    ro.observe(el);
    return () => ro.disconnect();
  });

  let host = $state("(host)");
  let cwd = $state("(./)");
  let model = $state("(unknown)");

  export function update_system(hostname: string, workingpath: string) {
    host = hostname;
    cwd = workingpath;
  }

  export function update_session(modelname: string) {
    model = modelname;
  }

  function hashHue(s: string): number {
    let hash = 0;
    for (let i = 0; i < s.length; i++) {
      hash = (hash * 31 + s.charCodeAt(i)) | 0;
    }
    return Math.abs(hash) % 360;
  }

  let sessionHue = $derived(hashHue(cwd || host || "enkaidu"));

  function auto_grow(e: Event) {
    let el = e.target as HTMLTextAreaElement;
    el.style.height = "auto";
    el.style.height = el.scrollHeight + "px";
    input_text = el.value;
  }

  function set_value(value: string, cursorAtStart = false) {
    if (!text_area) return;
    text_area.value = value;
    input_text = value;
    // auto-grow without faking an Event to avoid TS conversion warning
    text_area.style.height = "auto";
    text_area.style.height = text_area.scrollHeight + "px";
    const pos = cursorAtStart ? 0 : value.length;
    requestAnimationFrame(() => {
      if (text_area) {
        text_area.selectionStart = pos;
        text_area.selectionEnd = pos;
      }
    });
  }

  function isOnFirstLine(ta: HTMLTextAreaElement) {
    const pos = ta.selectionStart ?? 0;
    return !ta.value.slice(0, pos).includes("\n");
  }

  function isOnLastLine(ta: HTMLTextAreaElement) {
    const pos = ta.selectionStart ?? 0;
    return !ta.value.slice(pos).includes("\n");
  }

  async function syncPrompt(text: string) {
    history.push(text);
    // sync to server asynchronously, fire-and-forget
    history.syncToServer([text]).catch(() => {});
  }

  function handle_key_event(event: KeyboardEvent) {
    if (!text_area) return;
    const textarea = text_area;

    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault();
      const value = textarea.value;
      if (value.trim() !== "") {
        syncPrompt(value);
        if (onask) onask(value);
        set_value("");
      }
      return;
    }

    if (event.key === "ArrowUp") {
      if (isOnFirstLine(textarea)) {
        event.preventDefault();
        const prev = history.previous(textarea.value);
        if (prev !== null) {
          set_value(prev, true);
        }
      }
      return;
    }

    if (event.key === "ArrowDown") {
      if (isOnLastLine(textarea)) {
        event.preventDefault();
        const next = history.next();
        if (next !== null) {
          set_value(next, false);
        }
      }
      return;
    }
  }

  function handle_submit(event: Event) {
    event.preventDefault();
    if (onask && text_area) {
      const value = text_area.value;
      if (value.trim() !== "") {
        syncPrompt(value);
        onask(value);
      }
      set_value("");
    }
  }

  export function focus() {
    text_area?.focus();
  }
</script>

<div
  bind:this={root_el}
  class="w-full max-w-3xl mx-auto pl-1 pr-4 pb-4 pt-2"
  style="--session-hue: {sessionHue}"
>
  {#if host || cwd}
    <div
      class="promptbar-tab flex justify-between gap-2 rounded-t-xl border border-b-0 border-base-content/15 border-l-[3px] px-4 py-1.5 text-sm select-none"
      style="--session-hue: {sessionHue}"
    >
      <span class="font-semibold tracking-tight text-base-content/90">
        Enkaidu
      </span>
      <span class="truncate max-w-[25ch] font-medium text-base-content/70">
        {host}
      </span>
      <span class="truncate max-w-[45ch]" title={cwd}>{cwd}</span>
      <span class="font-semibold text-base-content/90 text-nowrap">
        {model}
      </span>
    </div>
  {/if}
  <form
    onsubmit={handle_submit}
    class="promptbar-input group flex items-center gap-2 border border-base-content/15 border-l-[3px] bg-base-200/70 px-4 py-3 shadow-sm transition-shadow focus-within:shadow-md focus-within:border-base-content/25 {host ||
    cwd
      ? 'rounded-b-xl border-t-0'
      : 'rounded-xl'}"
  >
    {#if loading}
      <div class="flex-1 flex items-center px-1">
        <div class="flex items-center gap-1.5">
          <span class="waiting-dot" style="--i: 0"></span>
          <span class="waiting-dot" style="--i: 1"></span>
          <span class="waiting-dot" style="--i: 2"></span>
        </div>
      </div>
    {:else}
      <textarea
        bind:this={text_area}
        onkeydown={handle_key_event}
        oninput={auto_grow}
        rows="1"
        class="flex-1 bg-transparent text-base-content placeholder:text-base-content/30 focus:outline-none resize-none text-base leading-relaxed"
        placeholder="Ask Enkaidu…"
      ></textarea>
      <button
        type="submit"
        disabled={input_text.trim() === ""}
        title="Send"
        aria-label="Send message"
        class="shrink-0 w-8 h-8 rounded-full bg-primary text-primary-content flex items-center justify-center text-sm transition-opacity disabled:opacity-30 disabled:cursor-not-allowed hover:opacity-80"
      >
        <svg
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2.5"
          stroke-linecap="round"
          stroke-linejoin="round"
          class="w-4 h-4"
        >
          <path d="M12 19V5" />
          <path d="M5 12l7-7 7 7" />
        </svg>
      </button>
    {/if}
  </form>
  {#if !loading}
    <div
      class="text-center text-xs text-base-content/80 mt-1 group-focus-within:opacity-0 transition-opacity"
    >
      Enter to send &bull; Shift+Enter for newline &bull; Up / Down for history
      &bull; AI can make mistakes: double-check responses.
    </div>
  {/if}
</div>
