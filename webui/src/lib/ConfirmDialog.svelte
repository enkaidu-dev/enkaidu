<script lang="ts">
  import { createEventDispatcher } from 'svelte';

  const dispatch = createEventDispatcher();

  export let command: string = "";
  export let id: string = "";
  export let show: boolean = false;

  function handleApprove() {
    dispatch('confirm', { id, approved: true });
  }

  function handleDeny() {
    dispatch('confirm', { id, approved: false });
  }
</script>

{#if show}
  <div class="modal modal-open">
    <div class="modal-box max-w-2xl">
      <h3 class="font-bold text-lg text-warning">⚠️ Command Confirmation Required</h3>
      <div class="py-4">
        <p class="mb-4">The assistant wants to run the following shell command:</p>
        <div class="mockup-code">
          <pre class="text-error"><code>{command}</code></pre>
        </div>
        <p class="mt-4 text-sm text-base-content/70">
          This command will be executed in your project directory. Please review it carefully before proceeding.
        </p>
      </div>
      <div class="modal-action">
        <button class="btn btn-error" on:click={handleDeny}>
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
          </svg>
          Deny
        </button>
        <button class="btn btn-success" on:click={handleApprove}>
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
          </svg>
          Allow
        </button>
      </div>
    </div>
    <div class="modal-backdrop opacity-50"></div>
  </div>
{/if}