<script lang="ts">
  import { onMount } from "svelte";
  import Markdown from "./Markdown.svelte";

  let {
    message,
    // True while this thinking block is the one actively receiving fragments
    // (i.e. it is the most recent entry). Drives auto-open + follow-along.
    active = false,
  }: {
    message: string;
    active?: boolean;
  } = $props();

  // Open/closed state, mirrored onto the <details open> attribute so the
  // chevron (group-open/think) and the body both react to it.
  let isOpen = $state(false);

  // Once the user manually toggles the card, their preference wins and we stop
  // auto-managing open/close (plan: "if the card is auto-opened and the user
  // closes it, it should stay closed").
  let user_locked = $state(false);

  // ---- Auto open (streaming) / auto collapse (done) -------------------------
  // Only applied while the user hasn't taken control (user_locked).
  $effect(() => {
    if (user_locked) return;
    isOpen = active;
  });

  // Intercept the summary click so we own the state change. preventDefault stops
  // the native <details> toggle; we flip isOpen ourselves.
  function toggle(e: Event) {
    e.preventDefault();
    user_locked = true;
    isOpen = !isOpen;
  }

  // ---- Follow-along (independent internal scroll) --------------------------
  // The expanded body has its own scroll region (bounded height +
  // overflow-y-auto), same as before, but now follows the newest text while it
  // is actively receiving — and only while the user is at (or near) the bottom
  // of *that* container. Mirrors item 15's at-bottom logic, scoped to the body,
  // and never touches the outer transcript scroll.
  const FOLLOW_TOLERANCE = 50; // px, "close enough" band inside the body
  let body_el: HTMLDivElement | undefined = $state(undefined);
  let think_at_bottom = $state(true);

  onMount(() => {
    const el = body_el;
    if (!el) return;
    const onscroll = () => {
      think_at_bottom =
        el.scrollTop + el.clientHeight >= el.scrollHeight - FOLLOW_TOLERANCE;
    };
    el.addEventListener("scroll", onscroll);
    return () => el.removeEventListener("scroll", onscroll);
  });

  // Follow the newest text while streaming + open + user at bottom. Reading
  // message.length registers content-growth as a dependency, so the effect
  // re-runs as fragments arrive. Setting scrollTop on the inner container only
  // affects that container — it does not scroll the page or drive the outer
  // transcript.
  $effect(() => {
    void message.length; // tracked dep -> re-run on each fragment
    if (active && isOpen && think_at_bottom && body_el) {
      body_el.scrollTop = body_el.scrollHeight;
    }
  });
</script>

<div class="w-7/8 place-self-start text-base-content/50">
  <details class="group/think" open={isOpen}>
    <summary
      class="cursor-pointer list-none py-0 text-xs font-medium text-base-content/40 hover:text-base-content/60 transition-colors select-none flex items-center gap-1"
      onclick={toggle}
    >
      <span
        class="text-base-content/30 group-open/think:rotate-90 transition-transform text-[0.85em] leading-none"
        >▶</span
      >
      Thinking
    </summary>
    <div
      class="text-base-content/60 ms-5 ps-2 mt-1 max-h-40 overflow-y-auto"
      bind:this={body_el}
    >
      <Markdown content={message} add_class="text-sm italic" />
    </div>
  </details>
</div>
