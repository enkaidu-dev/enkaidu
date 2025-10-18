<script lang="ts">
  import Copy from "virtual:icons/pixelarticons/copy";
  import CheckDouble from "virtual:icons/pixelarticons/check-double";

  let { copy_text }: { copy_text: string } = $props();

  let copy_label = $state("Copy");
  let copy_state = $state("");

  async function copy() {
    await navigator.clipboard.writeText(copy_text);
    copy_label = "Done";
    copy_state = "btn-neutral";
    setTimeout(() => {
      copy_label = "Copy";
      copy_state = "";
    }, 1000);
  }
</script>

<div class="absolute px-1 pe-2 w-full flex place-content-end">
  <div class="tooltip tooltip-bottom" data-tip="Copy">
    <button class="btn btn-outline btn-xs {copy_state}" onclick={copy}>
      {#if copy_state == ""}
        <Copy />
      {:else}
        <CheckDouble />
      {/if}
    </button>
  </div>
</div>
