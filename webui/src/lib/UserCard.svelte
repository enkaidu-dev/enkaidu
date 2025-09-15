<script lang="ts">
  let { message } = $props();
</script>

<div
  class="card bg-primary text-primary-content card-sm shadow-sm w-7/8 place-self-end"
>
  <div class="card-body text-base py-1">
    <h2 class="card-title text-sm">Query</h2>
    {message}
  </div>
</div>
