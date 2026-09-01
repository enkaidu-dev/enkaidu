<script lang="ts">
  import type { Component } from "svelte";

  /**
   * A single entry in the action bar rendered beneath a message's content.
   *
   * The containing card builds an array of these and hands it to
   * ContentUtilities, which renders whatever it is given. User and assistant
   * cards intentionally build different lists; a future action (regenerate,
   * thumbs up/down, quote, ...) is just one more object in the array.
   */
  export type UtilityAction = {
    id: string; // stable key for {#each}
    label: string; // tooltip + aria-label
    icon: Component;
    // Optional success-state flash: while the action's success state is
    // showing (1s after onAction resolves), these replace icon/label.
    success_icon?: Component;
    success_label?: string;
    onAction: () => void | Promise<void>;
  };

  let { actions }: { actions: UtilityAction[] } = $props();

  // id of the action currently showing its success state ("" = none)
  let success_id = $state("");

  // Bar is hover/focus-revealed, and pinned visible while a success flash
  // is showing so mouse users still see the "Done" feedback after the
  // button was blurred (see fire()).
  const bar_class = $derived(
    "flex items-center justify-end gap-1 select-none " +
      "opacity-0 group-hover:opacity-100 group-focus-within:opacity-100 " +
      "transition-opacity duration-150 " +
      (success_id !== "" ? "opacity-100" : "")
  );

  async function fire(action: UtilityAction, e?: MouseEvent) {
    // A mouse click (e.detail >= 1) leaves the button focused; that would
    // keep the bar revealed via group-focus-within after the cursor leaves.
    // Blur it for pointer clicks so the bar is hover-revealed only.
    // Keyboard activation (e.detail === 0) keeps focus for accessibility.
    if (e && e.detail !== 0) {
      (e.currentTarget as HTMLButtonElement).blur();
    }
    if (success_id !== "") return; // ignore clicks during a success flash
    try {
      await action.onAction();
    } catch {
      // e.g. clipboard rejected: no success flash, stay quiet
      return;
    }
    success_id = action.id;
    setTimeout(() => {
      success_id = "";
    }, 1000);
  }
</script>

<!-- Action bar beneath the message content (right-aligned, in-flow).
     Hidden until the surrounding `group` (the containing card) is hovered
     or keyboard focus enters it. -->
<div class={bar_class}>
  {#each actions as action (action.id)}
    {@const active = success_id === action.id}
    {@const Icon = active && action.success_icon ? action.success_icon : action.icon}
    {@const label = active ? (action.success_label ?? action.label) : action.label}
    <div class="tooltip tooltip-top" data-tip={label}>
      <button
        class="btn btn-ghost btn-xs"
        title={label}
        aria-label={label}
        onclick={(e) => fire(action, e)}
      >
        <Icon />
      </button>
    </div>
  {/each}
</div>
