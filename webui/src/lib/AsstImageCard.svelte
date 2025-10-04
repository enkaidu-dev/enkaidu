<script lang="ts">
  let { image_url }: { image_url: string } = $props();
</script>

<div
  class="card bg-base-300 text-base-content card-sm shadow-sm w-7/8 place-self-start py-1 dark:border-accent dark:border-1"
>
  <div class="card-body py-1">
    <h2 class="card-title text-sm text-accent">Assistant</h2>
    <img src={image_url} alt="Assistant's response" class="w-full" />
  </div>
</div>
