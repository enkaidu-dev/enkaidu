<script lang="ts">
  let { host, cwd }: { host: string; cwd: string } = $props();

  export function update(hostname, workingpath) {
    host = hostname;
    cwd = workingpath;
    }
</script>

<div
  class="menubar-strip flex items-center justify-between px-4 py-2 text-sm select-none"
>
  <span class="font-medium text-base-content/60"
     >Enkaidu<span class="text-base-content/40">:{window.location.port}</span
     ></span
   >
   <div class="flex items-center gap-4">
     <span class="truncate max-w-[30ch] text-base-content/45" title={cwd}>{cwd}</span>
     <span class="text-base-content/45">{host}</span>
   </div>
</div>
