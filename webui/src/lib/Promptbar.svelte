<script lang="ts">
  import { onMount } from "svelte";
  import { PromptHistory } from "./prompt_history";
  import HistorySearch from "./HistorySearch.svelte";
  import MacroPicker from "./MacroPicker.svelte";
  import FilePicker from "./FilePicker.svelte";

  let { onask = null, loading = false, closed = false } = $props();
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
  // When the user types "!" in the prompt bar, a dropdown lists available
  // macros filtered by the macro *name* — the text after "!" up to the first
  // space/tab/newline (a macro is one token, then its args).  The picker's one
  // job is to help *find* a name, so it is driven by the caret: open only while
  // the caret is on or within the name token, and closed the moment the user
  // moves into the arguments — which is what stops the picker from re-popping
  // while the user edits the args of a macro that already starts the prompt.
  // This replaces an earlier selection-lock that was created only on a dropdown
  // pick and so never covered a prompt that already started with a macro (from
  // a history load, a paste, or hand-typed).  Escape (and a no-match Enter)
  // gives a short-lived dismissal; arrow navigation and Enter/Escape selection
  // live in handle_key_event.
  let macro_picker_open = $state(false);
  let macro_sel = $state(0);
  // Set by Escape (and a no-match Enter) to suppress auto-open on caret
  // moves; cleared by the next typed input, so a dismiss is short-lived — it
  // won't bug the user again on the same text, but the next keystroke
  // re-engages finding.
  let macro_dismissed = $state(false);

  // Filter is the macro *name* portion only: text after "!" up to the first
  // whitespace (args live past it).  Empty filter shows the top macros.
  // Keeping it name-only stops an arg edit from reshuffling the filtered list
  // / jumping the highlighted row.
  let macro_filter = $derived.by(() => {
    const t = input_text;
    if (!t.startsWith("!")) return "";
    const rest = t.slice(1);
    const ws = rest.search(/[ \t\n]/);
    return ws === -1 ? rest : rest.slice(0, ws);
  });

  // Decide open/close from the caret's position relative to the name token.
  // Open while the caret is on or within the name; closed once it lands in the
  // arguments (just past the first whitespace after "!name").  A dismissed or
  // non-macro input stays closed.  Called from auto_grow (typing), onselect
  // (click / arrow caret moves) and set_value (programmatic set).
  function recompute_macro_picker() {
    if (!input_text.startsWith("!") || macros.length === 0) {
      macro_picker_open = false;
      macro_dismissed = false;
      return;
    }
    if (macro_dismissed) {
      macro_picker_open = false;
      return;
    }
    const ta = text_area;
    const caret = ta ? (ta.selectionStart ?? 0) : input_text.length;
    const rest = input_text.slice(1);
    const ws = rest.search(/[ \t\n]/);
    const nameEnd = ws === -1 ? input_text.length : 1 + ws;
    macro_picker_open = caret <= nameEnd;
  }

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
    // immediately start typing positional or named arguments.  set_value
    // places the caret just past that trailing space — in the argument
    // region — so recompute leaves the picker closed; re-finding happens only
    // if the user steps the caret back into the name.
    set_value(`!${macro.name} `);
    text_area?.focus();
  }

  // Close without dismissing (a backdrop click), so a later caret move into the
  // name still re-opens the picker.  Escape instead sets the short-lived
  // dismissal.
  function close_macro_picker() {
    macro_picker_open = false;
  }

  function auto_grow(e: Event) {
    let el = e.target as HTMLTextAreaElement;
    el.style.height = "auto";
    el.style.height = el.scrollHeight + "px";
    input_text = el.value;
    // A typed change always re-engages finding (clears any Escape dismissal)
    // and recomputes open/close from the caret position.
    macro_dismissed = false;
    recompute_macro_picker();
  }

  function set_value(
    value: string,
    caret: "start" | "end" | number = "end",
    programmatic = false,
  ) {
    const ta = text_area;
    if (!ta) return;
    ta.value = value;
    input_text = value;
    // A programmatic set (history load / recall / snippet insert) should not
    // auto-open the picker even when the text starts with "!"; mark it
    // dismissed so the recompute below keeps it closed until the user types.
    if (programmatic) macro_dismissed = true;
    // auto-grow without faking an Event to avoid TS conversion warning
    ta.style.height = "auto";
    ta.style.height = ta.scrollHeight + "px";
    // Set the caret synchronously so the next keydown sees a consistent
    // (value, selectionStart) pair. Deferring to requestAnimationFrame
    // desyncs value and caret for one frame, and isOnFirstVisualLine /
    // isOnLastVisualLine then evaluate a stale caret against the new value,
    // causing arrows to navigate history at unintended line positions.
    const pos =
      caret === "start" ? 0 : typeof caret === "number" ? caret : value.length;
    ta.setSelectionRange(pos, pos);
    recompute_macro_picker();
  }

  // A logical-line test ("does the caret see a \n?") is not enough: a long
  // sentence wraps to several *visual* rows, and the caret can sit on an upper
  // or lower wrapped row.  For history navigation we want to fire only when the
  // caret is on the *boundary visual row* — the very top row for ArrowUp, the
  // very bottom row for ArrowDown — so that pressing from a second-to-boundary
  // row just moves the caret within the wrap instead of jumping history.
  //
  // "On already at the boundary" is measured with a hidden mirror div that
  // reproduces the textarea's text layout (same font, width, padding,
  // line-height, wrapping rules).  The caret's vertical position and the total
  // content height are read from it, and we compare against whole line-heights
  // so a full-line gap (i.e. one row below the bottom / above the top) is
  // excluded.
  interface VisualRowInfo {
    caretH: number; // height of text up to the caret
    totalH: number; // height of the whole text
    lh: number; // rendered line-height in px
  }

  function measureVisualRows(ta: HTMLTextAreaElement): VisualRowInfo | null {
    const pos = ta.selectionStart ?? 0;
    const text = ta.value;
    if (text === "") return null;

    const cs = getComputedStyle(ta);
    const lh = parseFloat(cs.lineHeight) || parseFloat(cs.fontSize) * 1.2;

    const m = document.createElement("div");
    m.style.cssText = [
      "position:fixed",
      "top:-9999px",
      "left:0",
      "visibility:hidden",
      "width:" + ta.clientWidth + "px",
      "box-sizing:border-box",
      "border:0",
      "padding:" + cs.padding,
      "font-family:" + cs.fontFamily,
      "font-size:" + cs.fontSize,
      "font-weight:" + cs.fontWeight,
      "line-height:" + cs.lineHeight,
      "letter-spacing:" + cs.letterSpacing,
      "white-space:pre-wrap",
      "word-wrap:break-word",
      "overflow:hidden",
    ].join(";");

    document.body.appendChild(m);
    m.textContent = text;
    const totalH = m.offsetHeight;
    // A trailing zero-width space makes a partial row round up to its full
    // row height even when the text ends mid-row.
    m.textContent = text.slice(0, pos) + "\u200B";
    const caretH = m.offsetHeight;
    document.body.removeChild(m);

    return { caretH, totalH, lh };
  }

  function isOnFirstVisualLine(ta: HTMLTextAreaElement): boolean {
    const pos = ta.selectionStart ?? 0;
    // Another logical line precedes the caret → it is past the top row.
    if (ta.value.slice(0, pos).includes("\n")) return false;
    // Caret at the very start of the input → top row.
    if (pos === 0) return true;
    const info = measureVisualRows(ta);
    if (!info) return true;
    // On the top visual row ⇔ no full line-height of text sits above the
    // caret.  A wrapped 2nd/3rd row of the first sentence puts at least a
    // full line-height above it, so it is excluded.
    return info.caretH <= info.lh + 1;
  }

  function isOnLastVisualLine(ta: HTMLTextAreaElement): boolean {
    const pos = ta.selectionStart ?? 0;
    // Another logical line follows the caret → it is above the bottom row.
    if (ta.value.slice(pos).includes("\n")) return false;
    // Caret at the very end of the text → bottom row.
    if (pos >= ta.value.length) return true;
    const info = measureVisualRows(ta);
    if (!info) return true;
    // On the bottom visual row ⇔ the gap of text below the caret is less than a
    // full line-height.  A second-to-last wrapped row leaves a full line-height
    // below it, so it is excluded: only a caret actually on the bottom row
    // (gap ≈ 0) navigates history.
    return info.totalH - info.caretH < info.lh - 1;
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

  // If a request starts while any overlay is open, drop it rather
  // than let it reappear out from under the loading indicator.
  $effect(() => {
    if (loading) {
      hsearch_open = false;
      macro_picker_open = false;
      macro_dismissed = false;
      filepick_open = false;
    }
  });

  function open_history_search() {
    if (!loading) {
      hsearch_open = true;
      macro_picker_open = false;
      macro_dismissed = false;
      filepick_open = false;
    }
  }

  function on_history_select(text: string | null) {
    if (!hsearch_open) return; // ignore the trailing blur after a pick
    hsearch_open = false;
    // A history snippet drop is programmatic — pass programmatic so an
    // inserted macro prefix does not immediately re-pop the picker while the
    // user edits it.
    if (text !== null && text.trim() !== "") set_value(text, "end", true);
    text_area?.focus();
  }

  // ---- File picker (Spotlight-style) --------------------------------
  // ⌘F/Ctrl+F (while the textarea has focus, like the history hotkeys)
  // opens a FilePicker above the bar for inserting a file path without
  // the mouse: type a fragment, walk the listing with ↑/↓, Enter
  // inserts the chosen path.  The anchor is the textarea's selection
  // captured when the picker opened, so a selection is replaced by the
  // path; the caret lands just past it so the user keeps typing the
  // prompt.  A directory pick descends (inside the picker) instead of
  // inserting — see FilePicker.
  let filepick_open = $state(false);
  let filepick_anchor: { start: number; end: number } = { start: 0, end: 0 };

  function open_file_picker() {
    if (loading || closed) return;
    const ta = text_area;
    filepick_anchor = {
      start: ta?.selectionStart ?? 0,
      end: ta?.selectionEnd ?? 0,
    };
    filepick_open = true;
    hsearch_open = false;
    macro_picker_open = false;
    macro_dismissed = false;
  }

  function on_file_select(path: string | null) {
    if (!filepick_open) return; // ignore the trailing blur after a pick
    filepick_open = false;
    const ta = text_area;
    if (path === null || !ta) {
      ta?.focus();
      return;
    }
    // Splice the path in at the anchor captured on open (replacing any
    // selection) and park the caret just past it.  programmatic=true
    // marks the short-lived macro_dismissed, so a "!"-starting prompt
    // does not re-pop the macro picker around the insertion.
    const value = ta.value;
    const start = Math.min(filepick_anchor.start, value.length);
    const end = Math.min(filepick_anchor.end, value.length);
    set_value(
      value.slice(0, start) + path + value.slice(end),
      start + path.length,
      true,
    );
    text_area?.focus();
  }

  // When the textarea loses focus (Tab, click elsewhere, loading starts) we
  // close the picker.  Re-engaging is driven by the caret: a click or arrow that
  // moves into the name region still re-opens via onselect, and the next typed
  // character always recomputes.
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
        // Short-lived dismissal: stay closed on caret moves until the next
        // typed character re-engages finding.
        macro_dismissed = true;
        macro_picker_open = false;
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
          // No match — dismiss so the picker does not re-pop while the user
          // keeps typing (or submits) this line.
          macro_dismissed = true;
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

    // Cmd/Ctrl+F: open the file picker.  preventDefault stops the
    // browser's in-page find bar.  Shift+F is a different keystroke
    // (e.g. "Find Next") and is left alone.
    if (
      (event.ctrlKey || event.metaKey) &&
      event.key.toLowerCase() === "f" &&
      !event.shiftKey
    ) {
      event.preventDefault();
      open_file_picker();
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
      if (isOnFirstVisualLine(textarea)) {
        event.preventDefault();
        const prev = history.previous(textarea.value);
        if (prev !== null) {
          set_value(prev, "start", true);
        }
      }
      return;
    }

    if (event.key === "ArrowDown") {
      if (isOnLastVisualLine(textarea)) {
        event.preventDefault();
        const next = history.next();
        if (next !== null) {
          set_value(next, "end", true);
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
  {#if hsearch_open && !loading && !closed}
    <div
      class="fixed inset-0 z-50 flex items-end justify-center px-4 pb-[calc(var(--promptbar-h)+12px)] bg-base-100/40 backdrop-blur-[2px]"
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
  {#if macro_picker_open && !loading && !closed && !hsearch_open && !filepick_open}
    <div
      class="fixed inset-0 z-50 flex items-end justify-center px-4 pb-[calc(var(--promptbar-h)+12px)] bg-base-100/40 backdrop-blur-[2px]"
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
  <!-- File picker: same overlay pattern, opened with ⌘F/Ctrl+F to
       insert a file path into the prompt.  The backdrop click cancels
       (leaving the draft untouched) and refocuses the textarea. -->
  {#if filepick_open && !loading && !closed}
    <div
      class="fixed inset-0 z-50 flex items-end justify-center px-4 pb-[calc(var(--promptbar-h)+12px)] bg-base-100/40 backdrop-blur-[2px]"
      role="presentation"
      onpointerdown={(e) => {
        if (e.target === e.currentTarget) on_file_select(null);
      }}
    >
      <FilePicker onselect={on_file_select} />
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
    {:else if closed}
      <!-- Backend is shutting down: the input is gone entirely, so no prompt
           can be composed or sent. A one-line, icon-led notice tells the user
           there's nothing left to do but close the tab. -->
      <div
        class="flex-1 flex items-center justify-center gap-2 px-1 text-base-content/70 select-none"
        role="status"
        aria-label="Session ended. You may safely close this tab."
      >
        <svg
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
          class="w-5 h-5 shrink-0 text-base-content/50"
          aria-hidden="true"
        >
          <line x1="12" y1="2" x2="12" y2="12" />
          <path d="M18.36 6.64a9 9 0 1 1-12.73 0" />
        </svg>
        <span class="text-sm">
          Enkaidu has stopped. You may safely close this tab.
        </span>
      </div>
    {:else}
      <textarea
        bind:this={text_area}
        onkeydown={handle_key_event}
        oninput={auto_grow}
        onselect={() => recompute_macro_picker()}
        onblur={on_textarea_blur}
        rows="1"
        class="flex-1 bg-transparent text-base-content placeholder:text-base-content/30 focus:outline-none resize-none text-base leading-relaxed"
        placeholder="Ask Enkaidu… or type ! for macros"></textarea>
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
  {#if !loading && !closed}
    <div
      class="text-center text-xs text-base-content/80 mt-1 group-focus-within:opacity-0 transition-opacity"
    >
      Enter to send &bull; Shift+Enter for newline &bull; Up / Down for history
      &bull; &#8984;K / Ctrl+K (or &#8984;R / Ctrl+R) to search history &bull;
      &#8984;F / Ctrl+F for files
      {#if macros.length > 0}&bull; ! for macros{/if}
      &bull; AI can make mistakes: double-check responses.
    </div>
  {/if}
</div>
