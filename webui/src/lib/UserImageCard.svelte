<script lang="ts">
  let { image_url }: { image_url: string } = $props();
</script>

<div class="card bg-accent card-sm shadow-sm w-7/8 place-self-end">
  <div class="card-body py-1">
    <span><img src={image_url} alt="User query" class="object-fit" /></span>
  </div>
</div>
