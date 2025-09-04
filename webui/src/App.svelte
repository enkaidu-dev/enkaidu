<script lang="ts">
  import Menubar from "./lib/Menubar.svelte";
  import Promptbar from "./lib/Promptbar.svelte";
  import Session from "./lib/Session.svelte";
  import Sidebar from "./lib/Sidebar.svelte";
</script>

<main>
  <div class="drawer drawer-end">
    <input id="my-drawer" type="checkbox" class="drawer-toggle" />
    <div class="drawer-content">
      <Menubar />
      <Session />
      <Promptbar />
    </div>
    <Sidebar />
  </div>
</main>
