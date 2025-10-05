<script lang="ts">
  import * as Common from "../common_types";

  let {
    onsubmit,
    id,
    description,
    title,
    input_arguments,
    show = true,
  }: Common.InputDialogConfig & { onsubmit: Common.InputSubmit } = $props();

  let inputs: Common.InputValues = $state({});

  function handle_submit() {
    onsubmit(id, inputs);
    show = false;
    inputs = {};
  }
</script>

{#if show}
  <div class="modal modal-open">
    <div class="modal-box max-w-xl">
      <h3 class="font-bold text-lg">{title}</h3>
      {#if description}
        <div class="py-1">{description}</div>
      {/if}
      {#each input_arguments as arg}
        <fieldset class="fieldset">
          <legend class="fieldset-legend">{arg.name}</legend>
          <input
            type={arg.type}
            class="input w-full"
            bind:value={inputs[arg.name]}
          />
          {#if arg.description}
            <p class="label">{arg.description}</p>
          {/if}
        </fieldset>
      {/each}
      <div class="modal-action">
        <button class="btn btn-success" onclick={handle_submit}>
          Submit
        </button>
      </div>
    </div>
    <div class="modal-backdrop opacity-50"></div>
  </div>
{/if}
