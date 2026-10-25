<script lang="ts">
  import Markdown from "./Markdown.svelte";

  let {
    title,
    body,
    // True while this help card is the most recent entry in the transcript.
    // Drives auto-open; once any later event arrives this flips false and
    // the card auto-collapses (unless the user has locked it).
    active = false,
  }: {
    title: string;
    body: string;
    active?: boolean;
  } = $props();

  // Open/closed state, mirrored onto the <details open> attribute.
  let isOpen = $state(false);

  // Once the user manually toggles, their preference wins — we stop
  // auto-managing open/close from then on (mirrors AsstThinkCard).
  let user_locked = $state(false);

  // ---- Auto open when active / auto collapse when done ----------------------
  $effect(() => {
    if (user_locked) return;
    isOpen = active;
  });

  // Intercept the summary click so we own the state change.
  function toggle(e: Event) {
    e.preventDefault();
    user_locked = true;
    isOpen = !isOpen;
  }
</script>

<div class="w-7/8 place-self-start">
  <details
    class="group/help rounded-lg bg-info/5 border-l-[3px] border-l-info/50"
    open={isOpen}
  >
    <summary
      class="cursor-pointer list-none flex items-center gap-2 px-3 py-2.5
        text-sm text-base-content/70 hover:text-base-content/90
        transition-colors select-none"
      onclick={toggle}
    >
      <!-- help icon: question mark in a circle -->
      <svg
        xmlns="http://www.w3.org/2000/svg"
        class="h-4 w-4 shrink-0 stroke-current text-info/80"
        fill="none"
        viewBox="0 0 24 24"
        stroke-width="2"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          d="M9.879 7.519c1.171-1.005 3.071-1.005 4.242 0 1.172 1.005 1.172 2.647 0 3.652l-1.061 1.061M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z"
        />
      </svg>
      <span
        class="text-base-content/30 group-open/help:rotate-90
          transition-transform text-[0.85em] leading-none">▶</span
      >
      <span class="font-medium truncate">{title}</span>
    </summary>
    {#if isOpen}
      <div
        class="px-3 pb-3 pt-1 border-t border-base-200/60
          max-h-(--scrollable-max-h) overflow-y-auto"
      >
        <Markdown content={body} />
      </div>
    {/if}
  </details>
</div>
