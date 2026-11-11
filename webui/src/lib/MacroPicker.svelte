<script lang="ts">
  import { segments } from "./prompt_tokens";

  type Macro = { name: string; description: string; category: string };

  let {
    matches,
    sel,
    filter,
    onselect,
  }: {
    matches: Macro[];
    sel: number;
    filter: string;
    onselect: (macro: Macro) => void;
  } = $props();

  let items = $state<(HTMLLIElement | null)[]>([]);

  // Keep the highlighted row visible when it scrolls off the list.
  $effect(() => {
    items[sel]?.scrollIntoView({ block: "nearest" });
  });

  // The needle for highlighting matched portions of each macro name
  // (case-insensitive substring).  Computed once per render so each
  // `segments` call reuses it.
  let q = $derived(filter.trim().toLowerCase());
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
     overlay's backdrop-blur dismiss fires; onmousedown preventDefault
     keeps focus in the promptbar textarea when clicking the card or scrollbar.
     -->
<div
  onmousedown={(e) => e.preventDefault()}
  class="w-full max-w-2xl rounded-xl border border-base-content/20 bg-base-100
    shadow-2xl"
  role="listbox"
  tabindex="-1"
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
                    <mark class="bg-warning/25 text-inherit rounded-xs"
                      >{seg.text}</mark
                    >
                  {:else}
                    {seg.text}
                  {/if}
                {/each}
              </code>
              <span
                class="text-xs text-base-content/70 truncate"
                title={macro.description}>{macro.description}</span
              >
            </div>
            {#if macro.category}
              <div class="mt-0.5">
                <span
                  class="text-[0.65rem] uppercase tracking-wider
             text-base-content/60 bg-base-300/70 rounded px-1.5
             py-0.5 font-medium">{macro.category}</span
                >
              </div>
            {/if}
          </button>
        </li>
      {/each}
    </ul>
  {:else}
    <div class="px-4 py-3 text-sm text-base-content/65">No matching macros</div>
  {/if}
  <div
    class="flex items-center justify-end gap-3 px-4 py-2 border-t
        border-base-content/15 text-xs text-base-content/70 select-none"
  >
    <span>&uarr;&darr; to navigate</span>
    <span>Tab / Enter to select</span>
    <span>Esc to close</span>
  </div>
</div>
