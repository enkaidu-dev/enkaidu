<script lang="ts">
  let { message } = $props();
</script>

<div
  class="card bg-primary-content text-primary card-sm shadow-sm w-7/8 place-self-start"
>
  <div class="card-body">
    <h2 class="card-title">Assistant</h2>
    {message}
  </div>
</div>
