<script lang="ts">
  import { onMount } from "svelte";
  import { PromptHistory } from "./prompt_history";
  import HistorySearch from "./HistorySearch.svelte";
  import MacroPicker from "./MacroPicker.svelte";

  let { onask = null, loading = false } = $props();
  let text_area = $state<HTMLTextAreaElement | undefined>(undefined);
  let input_text = $state("");
  let root_el = $state<HTMLDivElement | null>(null);

  const history = new PromptHistory({ maxSize: 200 });

  // PromptHistory mutates its plain array in place, which Svelte can't
  // track. This counter is bumped on every change so live_entries below
  // re-reads the snapshot (consumed by the Ctrl+R search panel).
  let history_version = $state(0);

  // Load history from server once on mount
  $effect(() => {
    history.loadFromServer().then(() => {
      history_version++;
    });
  });

  let live_entries = $derived.by(() => {
    void history_version;
    return [...history.entriesSnapshot];
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

  type Macro = { name: string; description: string; category: string };
  type AllMacros = Macro[];

  let host = $state("(host)");
  let cwd = $state("(./)");
  let model = $state("(unknown)");
  let macros: AllMacros = $state([]);

  export function update_system(
    hostname: string,
    workingpath: string,
    all_macros: AllMacros,
  ) {
    host = hostname;
    cwd = workingpath;
    macros = all_macros;
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

  // ---- Macro picker --------------------------------------------------
  // When the user types "!" in the prompt bar, a dropdown lists all
  // available Enkaidu macros, filtered by the text after "!".  Arrow
  // keys navigate, Enter selects (inserting "!name "), Escape dismisses.
  // After a selection the picker stays closed while the user types args,
  // and reopens if the "!" portion is backspaced or a new "!…" prompt is
  // started.
  let macro_picker_open = $state(false);
  let macro_sel = $state(0);
  // The completed "!name " string; the lock keeps the picker closed
  // while the user appends positional or named arguments after it.
  let macro_locked_value: string | null = null;

  // Text after "!" is the filter; empty filter shows all macros.
  let macro_filter = $derived(
    input_text.startsWith("!") ? input_text.slice(1) : "",
  );

  let macro_matches = $derived.by(() => {
    if (!macro_picker_open || macros.length === 0) return [] as Macro[];
    const q = macro_filter.trim().toLowerCase();
    if (!q) return macros.slice(0, 20);
    return macros
      .filter(
        (m) =>
          m.name.toLowerCase().includes(q) ||
          m.description.toLowerCase().includes(q) ||
          m.category.toLowerCase().includes(q),
      )
      .slice(0, 20);
  });

  // Reset to the top of the filtered list whenever the filter text
  // changes so a narrowing query doesn't leave a stale highlight.
  $effect(() => {
    void macro_filter;
    macro_sel = 0;
  });

  function on_macro_select(macro: Macro) {
    // Insert the macro name with a trailing space so the user can
    // immediately start typing positional or named arguments.
    set_value(`!${macro.name} `);
    macro_locked_value = `!${macro.name} `;
    macro_picker_open = false;
    text_area?.focus();
  }

  function close_macro_picker() {
    macro_picker_open = false;
    macro_locked_value = null;
  }

  function auto_grow(e: Event) {
    let el = e.target as HTMLTextAreaElement;
    el.style.height = "auto";
    el.style.height = el.scrollHeight + "px";
    input_text = el.value;

    // Macro picker activation: opens when the input starts with "!" and
    // there are macros; stays closed after a completed selection while
    // the user appends args (lock); clears lock when the "!" prefix
    // changes so a new macro can be picked.
    if (input_text.startsWith("!") && macros.length > 0) {
      if (
        macro_locked_value !== null &&
        input_text.startsWith(macro_locked_value)
      ) {
        // User is on the same macro they just completed — stay closed.
        macro_picker_open = false;
      } else {
        // New "!" prefix or the lock has been invalidated by backspacing
        // into the name — pick again.
        macro_locked_value = null;
        macro_picker_open = true;
      }
    } else {
      // Not in macro mode.
      macro_picker_open = false;
      macro_locked_value = null;
    }
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
    history_version++;
  }

  // ---- Prompt-history search (Spotlight-style) ----------------------
  // Bindings: Cmd/Ctrl+K (web-app command-palette convention) and
  // Cmd/Ctrl+R (shell reverse-search muscle memory). Both only clash
  // with browser "reload"/"focus address bar" while the textarea has
  // focus; elsewhere the browser keeps its bindings.
  let hsearch_open = $state(false);

  // If a request starts while either overlay is open, drop it rather
  // than let it reappear out from under the loading indicator.
  $effect(() => {
    if (loading) {
      hsearch_open = false;
      macro_picker_open = false;
      macro_locked_value = null;
    }
  });

  function open_history_search() {
    if (!loading) {
      hsearch_open = true;
      macro_picker_open = false;
      macro_locked_value = null;
    }
  }

  function on_history_select(text: string | null) {
    if (!hsearch_open) return; // ignore the trailing blur after a pick
    hsearch_open = false;
    if (text !== null && text.trim() !== "") set_value(text);
    text_area?.focus();
  }

  // When the textarea loses focus (Tab, click elsewhere, loading starts),
  // close the macro picker but leave the lock intact so resuming the same
  // prompt doesn't re-pop the picker.
  function on_textarea_blur() {
    if (macro_picker_open) macro_picker_open = false;
  }

  function handle_key_event(event: KeyboardEvent) {
    if (!text_area) return;
    const textarea = text_area;

    // When the macro picker is open, intercept navigation keys before
    // the general input handling so arrows/enter/esc don't fall
    // through to history navigation or form submission.
    if (macro_picker_open) {
      if (event.key === "Escape") {
        event.preventDefault();
        close_macro_picker();
        return;
      }
      if (event.key === "ArrowDown") {
        event.preventDefault();
        if (macro_matches.length > 0) {
          macro_sel = (macro_sel + 1) % macro_matches.length;
        }
        return;
      }
      if (event.key === "ArrowUp") {
        event.preventDefault();
        if (macro_matches.length > 0) {
          macro_sel =
            (macro_sel - 1 + macro_matches.length) % macro_matches.length;
        }
        return;
      }
      if (event.key === "Enter" && !event.shiftKey) {
        event.preventDefault();
        const selected = macro_matches[macro_sel];
        if (selected) {
          on_macro_select(selected);
        } else {
          // No match — close the picker so the user can continue typing.
          macro_picker_open = false;
        }
        return;
      }
    }

    // Cmd/Ctrl+K (command-palette convention) and Cmd/Ctrl+R (shell
    // reverse search): open history search. preventDefault keeps the
    // browser from reloading / jumping to the address bar.
    if (
      (event.ctrlKey || event.metaKey) &&
      ["r", "k"].includes(event.key.toLowerCase())
    ) {
      event.preventDefault();
      open_history_search();
      return;
    }

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

  // Land the caret in the prompt bar on page load so the user can
  // start typing immediately (the textarea is already mounted — its
  // waiting-dots replacement only exists while a request is in
  // flight, which isn't the case on first load).
  onMount(() => {
    text_area?.focus();
  });
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
  <!-- Spotlight-style overlay (history search): bottom-anchored 12px
       above the prompt bar (the bar publishes its live height as
       --promptbar-h on <html>, so the card tracks it), growing upward,
       with the dimmed/blur backdrop covering the rest of the viewport.
       Clicking the backdrop (not the card) dismisses the draft. -->
  {#if hsearch_open && !loading}
    <div
      class="fixed inset-0 z-50 flex items-end justify-center px-4 pb-[calc(var(--promptbar-h)_+_12px)] bg-base-100/40 backdrop-blur-[2px]"
      role="presentation"
      onpointerdown={(e) => {
        if (e.target === e.currentTarget) on_history_select(null);
      }}
    >
      <HistorySearch entries={live_entries} onselect={on_history_select} />
    </div>
  {/if}
  <!-- Macro picker: same overlay pattern, shown when the user starts
       typing "!" in the prompt.  The backdrop click dismisses the
       picker and refocuses the textarea. -->
  {#if macro_picker_open && !loading && !hsearch_open}
    <div
      class="fixed inset-0 z-50 flex items-end justify-center px-4 pb-[calc(var(--promptbar-h)_+_12px)] bg-base-100/40 backdrop-blur-[2px]"
      role="presentation"
      onpointerdown={(e) => {
        if (e.target === e.currentTarget) {
          close_macro_picker();
          text_area?.focus();
        }
      }}
    >
      <MacroPicker
        matches={macro_matches}
        sel={macro_sel}
        filter={macro_filter}
        onselect={on_macro_select}
      />
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
        onblur={on_textarea_blur}
        rows="1"
        class="flex-1 bg-transparent text-base-content placeholder:text-base-content/30 focus:outline-none resize-none text-base leading-relaxed"
        placeholder="Ask Enkaidu… or type ! for macros"
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
      &bull; &#8984;K / Ctrl+K (or &#8984;R / Ctrl+R) to search history
      {#if macros.length > 0}&bull; ! for macros{/if}
      &bull; AI can make mistakes: double-check responses.
    </div>
  {/if}
</div>
