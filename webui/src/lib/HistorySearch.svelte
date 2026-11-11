<script lang="ts">
  import type { PromptHistoryEntry } from "./prompt_history";
  import { segments } from "./prompt_tokens";

  let {
    entries,
    onselect,
  }: {
    entries: readonly PromptHistoryEntry[];
    onselect: (text: string | null) => void;
  } = $props();

  const MAX_RESULTS = 12;

  let input = $state<HTMLInputElement | undefined>(undefined);
  let panel_root = $state<HTMLDivElement | undefined>(undefined);
  let query = $state("");
  let sel = $state(0);
  let items = $state<(HTMLLIElement | null)[]>([]);

  $effect(() => {
    input?.focus();
  });

  let q = $derived(query.trim().toLowerCase());

  // Newest first; empty query shows recents (Spotlight behavior),
  // otherwise case-insensitive substring matches.
  let matches = $derived.by(() => {
    const newest_first = [...entries].reverse();
    const m = q
      ? newest_first.filter((e) => e.text.toLowerCase().includes(q))
      : newest_first;
    return m.slice(0, MAX_RESULTS);
  });

  // Keep the selection valid when the filtered list shrinks.
  $effect(() => {
    if (sel >= matches.length) sel = Math.max(0, matches.length - 1);
  });

  // Like Spotlight, each keystroke re-anchors to the best (top) match.
  $effect(() => {
    void q;
    sel = 0;
  });

  // Keep the highlighted row visible while navigating a capped list.
  $effect(() => {
    items[sel]?.scrollIntoView({ block: "nearest" });
  });

  function select(entry: PromptHistoryEntry | null) {
    onselect(entry ? entry.text : null);
  }

  function on_key(event: KeyboardEvent) {
    if (event.isComposing || event.keyCode === 229) return;
    // ⌘K/Ctrl+K and ⌘R/Ctrl+R while the search is open just close it
    // (never trigger the browser's address-bar/reload behavior).
    if (
      (event.ctrlKey || event.metaKey) &&
      ["r", "k"].includes(event.key.toLowerCase())
    ) {
      event.preventDefault();
      onselect(null);
      return;
    }
    if (event.key === "Enter") {
      event.preventDefault(); // pick, do NOT submit a prompt
      select(matches[sel] ?? null);
    } else if (event.key === "ArrowDown") {
      event.preventDefault();
      if (matches.length) sel = (sel + 1) % matches.length;
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      if (matches.length) sel = (sel - 1 + matches.length) % matches.length;
    } else if (event.key === "Escape") {
      event.preventDefault();
      onselect(null);
    }
  }

  // Clicking/tapping outside the panel dismisses it without changing
  // the draft. pointerdown on a result fires before this blur, so
  // result clicks land first and close normally.
  function on_blur(event: FocusEvent) {
    if (
      panel_root &&
      event.relatedTarget !== null &&
      !panel_root.contains(event.relatedTarget as Node)
    ) {
      onselect(null);
    }
  }
</script>

<!-- Self-contained Spotlight-style card: positioned by the overlay
     wrapper in Promptbar, so it carries its own full chrome. -->
<div
  bind:this={panel_root}
  role="presentation"
  onmousedown={(e) => {
    if (e.target !== input) e.preventDefault();
  }}
  class="w-full max-w-xl rounded-xl border border-base-content/20 bg-base-100 shadow-2xl"
>
  <div class="flex items-center gap-2.5 px-4 pt-3 pb-1.5 text-sm">
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      class="w-4 h-4 shrink-0 text-base-content/40"
    >
      <circle cx="11" cy="11" r="7" />
      <path d="M21 21l-4.35-4.35" />
      <path d="M11 8v3l2 2" />
    </svg>
    <input
      bind:this={input}
      bind:value={query}
      onkeydown={on_key}
      onblur={on_blur}
      class="flex-1 bg-transparent focus:outline-none text-base-content placeholder:text-base-content/50"
      placeholder="Search prompt history…"
      aria-label="Search prompt history"
      autocomplete="off"
      spellcheck="false"
    />
    <span
      class="text-xs text-base-content/65 select-none shrink-0"
      title="Matched / total entries"
    >
      {matches.length} / {entries.length}
    </span>
  </div>
  {#if matches.length}
    <ul class="px-1.5 pb-1.5 max-h-64 overflow-y-auto" role="listbox">
      {#each matches as entry, i (entry.id)}
        <li bind:this={items[i]}>
          <button
            type="button"
            title={entry.text}
            onpointerdown={() => select(entry)}
            class="w-full text-left px-2.5 py-1.5 rounded-lg truncate text-sm transition-colors {i ===
            sel
              ? 'bg-accent/15 text-base-content'
              : 'text-base-content/75'}"
          >
            {#each segments(entry.text, q) as seg}
              {#if seg.hit}
                <mark class="bg-warning/25 text-inherit rounded-xs"
                  >{seg.text}</mark
                >
              {:else}
                {seg.text}
              {/if}
            {/each}
          </button>
        </li>
      {/each}
    </ul>
  {:else}
    <div class="px-4 pb-2.5 text-sm text-base-content/65">
      No matching prompts
    </div>
  {/if}
  <div
    class="flex items-center justify-end gap-3 px-4 py-2 border-t border-base-content/15 text-xs text-base-content/70 select-none"
  >
    <span>&uarr;&darr; to navigate</span>
    <span>Enter to select</span>
    <span>Esc to close</span>
  </div>
</div>
