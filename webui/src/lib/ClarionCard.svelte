<script lang="ts">
  let { subject }: { subject: string } = $props();
</script>

<div
  role="alert"
  class="w-7/8 place-self-start flex items-center gap-2.5 px-3 py-2 rounded-lg text-sm text-base-content/80 bg-error/8 border-l-[3px] border-l-error/70"
>
    <svg
    xmlns="http://www.w3.org/2000/svg"
    class="h-4 w-4 shrink-0 stroke-current text-error"
    fill="none"
    viewBox="0 0 24 24"
     >
      <path
      stroke-linecap="round"
      stroke-linejoin="round"
      stroke-width="2"
      d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
      />
    </svg>
    <span>{subject}</span>
</div>
