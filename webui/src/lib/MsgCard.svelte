<script lang="ts">
  import Markdown from "./Markdown.svelte";

  let {
    message,
    level,
    details,
  }: { message?: string; level: string; details?: string } = $props();

  let badge_style = $state(level || "info");
  switch (level) {
    case "warn":
      badge_style = "warning";
      break;
  }
</script>

<div
  class="indicator w-7/8 p-1 card card-sm shadow-sm place-self-start bg-neutral-content"
>
  <span class="indicator-item badge badge-{badge_style} badge-sm"
    >{level || "info"}</span
  >
  {#if details}
    <div class="collapse collapse-arrow">
      <input type="checkbox" />
      <div class="collapse-title card-title text-sm">
        {message}
      </div>
      <div class="collapse-content text-sm">
        <Markdown content={details} />
      </div>
    </div>
  {:else}
    <span>{message}</span>
  {/if}
</div>
