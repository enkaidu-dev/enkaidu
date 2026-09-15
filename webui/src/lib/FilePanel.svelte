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

  function file_name(): string {
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
  let hl_lang = $derived(file_name().split(".").pop()?.toLowerCase() ?? "");
  let highlighted = $derived(highlight_source(body, hl_lang));

  // Unlike the transcript, files arrive complete (no streaming churn),
  // so the block mounts once per open/replacement rather than needing
  // debounced hydration. Re-mounting on every change is cheap here and
  // keeps the block components' internal state (view toggle, failed…)
  // fresh per file.
  //
  // The host is `display: contents`, so the block's panel-mode fragment
  // — its bar row and its body — become flex items of the aside itself:
  // ONE bar at the top (path + the block's own toggle/save chips + close)
  // and content filling the rest. The block's chrome *is* the panel's
  // chrome; that's the integration being asked for.
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
        language: path,
        saves: block.saves ?? [],
        saveBasename: save_stem(),
        mode: "panel",
        onclose,
      },
    });
    return () => {
      el.replaceChildren();
      unmount(instance);
    };
  });

  // One persistent delegated listener on the (stable) aside element: it
  // outlives every re-mount and reaches the Copy chips mounted inside.
  let panel_root = $state<HTMLElement | null>(null);

  $effect(() => {
    const el = panel_root;
    if (!el) return;
    el.addEventListener("click", handle_copy_click);
    return () => el.removeEventListener("click", handle_copy_click);
  });
</script>

<aside
  class="filepanel h-full min-w-[20rem] flex flex-col overflow-hidden border-l border-base bg-base-100"
  style={width != null ? `width: ${width}px` : "width: 50%"}
  bind:this={panel_root}
>
  {#snippet header()}
    <div
      class="flex shrink-0 items-center gap-2 border-b border-base bg-base-200 px-3 py-2"
    >
      <span class="min-w-0 flex-1 truncate font-mono text-xs" title={path}>
        {path}
      </span>
      <button
        type="button"
        class="action-chip shrink-0"
        onclick={() => onclose?.()}
        title="Close panel"
        aria-label="Close panel"
      >
        ✕
      </button>
    </div>
  {/snippet}

  {#if loading}
    <!-- loading/error deliberately take precedence over `block`: during
         the fetch the body is empty, which would (momentarily) render an
         empty/failed block instead of the loading state. -->
    {@render header()}
    <p class="p-3 text-sm text-base-content/50">
      Loading {file_name()}…
    </p>
  {:else if error}
    {@render header()}
    <p
      class="m-3 rounded-md border-l-[3px] border-error/70 bg-error/8 p-2 text-sm text-base-content/80"
    >
      {error}
    </p>
  {:else if block}
    <!-- The mounted block renders its own panel-mode fragment: bar (path
         label + view toggle + save chips + close) and filling body. -->
    <div class="contents" bind:this={mount_target}></div>
  {:else}
    {@render header()}
    <div class="enkaidu-code group/code relative min-h-0 flex-1">
      <button
        type="button"
        data-copy-code
        aria-label="Copy file"
        class="enkaidu-copy absolute right-2 top-2 z-10 opacity-0 transition-opacity duration-150 group-hover/code:opacity-100 focus-visible:opacity-100"
      >Copy</button>
      <pre
        class="h-full overflow-auto whitespace-pre-wrap wrap-break-word p-3 font-mono text-xs leading-5 text-base-content/90"><code
          class="hljs language-{hl_lang}">{@html highlighted}</code></pre>
    </div>
  {/if}
</aside>
