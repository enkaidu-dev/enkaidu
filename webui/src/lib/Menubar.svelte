<script lang="ts">
  import Folder from "virtual:icons/pixelarticons/folder";
  import Server from "virtual:icons/pixelarticons/server";

  let { host, cwd }: { host: string; cwd: string } = $props();

  export function update(hostname, workingpath) {
    host = hostname;
    cwd = workingpath;
  }
</script>

<div
  class="navbar bg-secondary text-secondary-content min-h-auto py-2 shadow-md justify-between"
>
  <span
    ><kbd class="kbd kbd-xl text-secondary">Enkaidu</kbd>
    <b>:{window.location.port}</b></span
  >
  <div class="badge badge-lg badge-secondary">
    <Folder /> <b>{cwd}</b>
  </div>

  <div class="badge badge-lg badge-secondary">
    <Server /><b>{host}</b>
  </div>
  <!-- <label for="my-drawer" class="btn btn-ghost drawer-button"> &lt;&lt; </label> -->
</div>
