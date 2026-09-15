<script lang="ts">
  import { mount, unmount } from "svelte";
  import { file_renderer } from "./blocks/registry";
  import { highlight_source } from "../markdown";
  import { handle_copy_click } from "./copy";

  let {
    path,
    body,
    loading = false,
    error = "",
    onclose,
    width,
  }: {
    path: string;
    body: string;
    loading?: boolean;
    error?: string;
    onclose?: () => void;
    width?: number;
  } = $props();

  function file_name() {
    const parts = path.split("/").filter(Boolean);
    return parts.length > 0 ? parts[parts.length - 1] : path;
  }

  // Download filename stem for the blocks' save chips: the file name up
  // to its first dot (README.md → README, chart.vl.json → chart).
  function save_stem(): string {
    const name = file_name();
    const dot = name.indexOf(".");
    return dot > 0 ? name.slice(0, dot) : name;
  }

  // Renderable extension → interactive block renderer (mermaid/svg/csv/
  // markdown/vega-json). Undefined ⇒ the raw highlighted-text fallback.
  let block = $derived(file_renderer(path, body));

  // Highlight language guess for the fallback view: the extension,
  // falling back to plaintext inside highlight_source.
  let hl_lang = $derived(
    file_name().split(".").pop()?.toLowerCase() ?? "",
  );
  let highlighted = $derived(highlight_source(body, hl_lang));

  // Unlike the transcript, files arrive complete (no streaming churn),
  // so the block mounts once per open/replacement rather than needing
  // debounced hydration. Re-mounting on every change is cheap here and
  // keeps the block components' internal state (view toggle, failed…)
  // fresh per file.
  let mount_target = $state<HTMLDivElement | null>(null);

  $effect(() => {
    const el = mount_target;
    if (!el || !block) return;
    // Re-reads of path/body re-run this effect; tear the old instance
    // down first (the cleanup below also fires on component teardown).
    el.replaceChildren();
    const instance = mount(block.component, {
      target: el,
      props: {
        source: body,
        language: block.language,
        saves: block.saves ?? [],
        saveBasename: save_stem(),
      },
    });
    return () => {
      el.replaceChildren();
      unmount(instance);
    };
  });

  // One persistent delegated listener covers every Copy chip (including
  // BlockFrame's own chip inside the mounted block's code view), same
  // pattern as Markdown.svelte.
  let panel_body = $state<HTMLElement | null>(null);

  $effect(() => {
    const el = panel_body;
    if (!el) return;
    el.addEventListener("click", handle_copy_click);
    return () => el.removeEventListener("click", handle_copy_click);
  });
</script>

<aside
  class="filepanel h-full min-w-[20rem] flex flex-col overflow-hidden border-l border-base bg-base-100"
  style={width != null ? `width: ${width}px` : "width: 50%"}
>
  <div
    class="flex items-center gap-2 border-b border-base bg-base-200 px-3 py-2"
  >
    <span class="min-w-0 flex-1 truncate font-mono text-xs" title={path}>
      {path}
    </span>
    <button
      type="button"
      class="action-chip"
      onclick={() => onclose?.()}
      title="Close panel"
      aria-label="Close panel"
    >
      ✕
    </button>
  </div>

  <div class="min-h-0 flex-1 overflow-auto" bind:this={panel_body}>
    {#if loading}
      <p class="p-3 text-sm text-base-content/50">
        Loading {file_name()}…
      </p>
    {:else if error}
      <p
        class="m-3 rounded-md border-l-[3px] border-error/70 bg-error/8 p-2 text-sm text-base-content/80"
      >
        {error}
      </p>
    {:else if block}
      <div class="p-1.5" bind:this={mount_target}></div>
    {:else}
      <div class="enkaidu-code group/code relative">
        <button
          type="button"
          data-copy-code
          aria-label="Copy file"
          class="enkaidu-copy absolute right-2 top-2 z-10 opacity-0 transition-opacity duration-150 group-hover/code:opacity-100 focus-visible:opacity-100"
        >Copy</button>
        <pre
          class="whitespace-pre-wrap wrap-break-word p-3 font-mono text-xs leading-5 text-base-content/90"><code
            class="hljs language-{hl_lang}">{@html highlighted}</code></pre>
      </div>
    {/if}
  </div>
</aside>
