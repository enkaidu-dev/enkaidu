<script lang="ts">
  type Macro = { name: string; description: string; category: string };

  let { matches, sel, filter, onselect } = $props<{
    matches: Macro[];
    sel: number;
    filter: string;
    onselect: (macro: Macro) => void;
  }>();

  let items = $state<(HTMLLIElement | null)[]>([]);

  // Keep the highlighted row visible when it scrolls off the list.
  $effect(() => {
    items[sel]?.scrollIntoView({ block: "nearest" });
  });

  // The needle for highlighting matched portions of each macro name
  // (case-insensitive substring).  Computed once per render so each
  // `segments` call reuses it.
  let q = $derived(filter.trim().toLowerCase());

  // Split a text value into matched / unmatched segments for
  // highlighting the filter substring in the macro name.
  // Mirrors HistorySearch's `segments` helper.
  type Segment = { text: string; hit: boolean };
  function segments(text: string, needle: string): Segment[] {
    if (!needle) return [{ text, hit: false }];
    const lower = text.toLowerCase();
    const out: Segment[] = [];
    let i = 0;
    let ix = lower.indexOf(needle);
    while (ix !== -1) {
      if (ix > i) out.push({ text: text.slice(i, ix), hit: false });
      out.push({ text: text.slice(ix, ix + needle.length), hit: true });
      i = ix + needle.length;
      ix = lower.indexOf(needle, i);
    }
    if (i < text.length) out.push({ text: text.slice(i), hit: false });
    return out;
  }
</script>

<!--
    Dropdown card shown above the promptbar when the user types "!" in
    an empty prompt.  Each row presents an Enkaidu macro with:
        • `!name` in monospace with the matched portion highlighted
        • a short description
        • a small category tag

    Keyboard navigation (arrow keys, Enter, Escape) is handled by
     the parent Promptbar via the textarea's keydown handler.
     Click-to-select uses onpointerdown so it lands before the
     overlay's backdrop-blur dismiss fires.
     -->
<div
  class="w-full max-w-2xl rounded-xl border border-base-content/20 bg-base-100
    shadow-2xl"
  role="listbox"
>
  {#if matches.length}
    <ul class="px-1.5 py-1.5 max-h-52 overflow-y-auto">
      {#each matches as macro, i (macro.name)}
        <li bind:this={items[i]}>
          <button
            type="button"
            onpointerdown={() => onselect(macro)}
            class="w-full text-left px-3 py-2 rounded-lg transition-colors
         {i === sel
              ? 'bg-accent/12 text-base-content'
              : 'text-base-content/75'}"
          >
            <div class="flex items-baseline gap-2">
              <code
                class="text-sm font-medium text-accent shrink-0"
                title={macro.description}
                >!
                {#each segments(macro.name, q) as seg}
                  {#if seg.hit}
                    <mark class="bg-warning/25 text-inherit rounded-[2px]"
                      >{seg.text}</mark
                    >
                  {:else}
                    {seg.text}
                  {/if}
                {/each}
              </code>
              <span
                class="text-xs text-base-content/55 truncate"
                title={macro.description}>{macro.description}</span
              >
            </div>
            {#if macro.category}
              <div class="mt-0.5">
                <span
                  class="text-[0.62rem] uppercase tracking-wider
             text-base-content/40 bg-base-300/60 rounded px-1.5
             py-0.5 font-medium">{macro.category}</span
                >
              </div>
            {/if}
          </button>
        </li>
      {/each}
    </ul>
  {:else}
    <div class="px-4 py-3 text-sm text-base-content/40">No matching macros</div>
  {/if}
  <div
    class="flex items-center gap-3 px-3 py-1.5 border-t
        border-base-content/10 text-[0.7rem] text-base-content/30"
  >
    <span>&uarr;&darr; to navigate</span>
    <span>Enter to select</span>
    <span>Esc to close</span>
  </div>
</div>
