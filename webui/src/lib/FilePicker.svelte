<script lang="ts">
  import { segments } from "./prompt_tokens";

  // Spotlight-style file browser for the Promptbar. Opened either by
  // ⌘F/Ctrl+F (a free open, an empty query) or by the user typing a `./` path
  // in the prompt bar (the query is seeded with that token so the picker
  // continues it — see Promptbar's `recompute_file_picker`).
  // The user types a path fragment: the *directory* part (everything up
  // to and including the last "/") is listed from the server via
  // GET /fs/list?path=… (relative paths resolve against the server's
  // working directory; paths outside it come back as 403), and the
  // remainder is a local case-insensitive filter over the listing — so
  // a fetch fires only when the directory part changes, never per
  // filtered keystroke.
  //
  // Enter always accepts and inserts the chosen path (file or directory) —
  // or if nothing is highlighted in the listing, accepts the typed `query`
  // as-is.  Tab completes/descends into a highlighted directory (growing the
  // typed path, like shell Tab completion) or accepts a highlighted file.
  // Esc, ⌘F/Ctrl+F again, a backdrop click, or focus leaving the card all
  // dismiss via onselect(null) without touching the draft.
  // (Promptbar owns the overlay; this card is display + pointer + its own
  // keyboard/input, and reports results back through `onselect`.)
  let {
    onselect,
    seed = "",
  }: {
    onselect: (path: string | null) => void;
    // Pre-fills the query on open: "" for a bare ⌘F, or the `./` path token
    // for the typing trigger.  Captured once at mount — the overlay remounts
    // on every open, so each open starts from a fresh seed.
    seed?: string;
  } = $props();

  const MAX_RESULTS = 50;
  const DEBOUNCE_MS = 120;

  let input = $state<HTMLInputElement | undefined>(undefined);
  let panel_root = $state<HTMLDivElement | undefined>(undefined);
  let query = $state("");
  let sel = $state(0);
  let items = $state<(HTMLLIElement | null)[]>([]);

  // A directory entry (descendable) or a file entry (the backend's
  // { name, type } record; `type` is the OS info string, e.g. "regular
  // file" or "symbolic link").
  type FsEntry = { name: string; is_dir: boolean; type?: string };

  let entries: FsEntry[] = $state([]);
  let listed_dir = $state(""); // the path the server actually listed
  let listing = $state(false);
  let error = $state("");

  // Split the typed path into (dir, frag) as two separate *string*
  // deriveds (deliberately not one object): `dir` is everything up to and
  // including the last "/" ("" means the server's cwd), `frag` is the rest.
  // A space is a legal path character and stays part of the fragment.
  //
  // Keeping `dir` its own string is what lets the listing effect below fire
  // only when the *directory* changes: Svelte's object.is dirty-check leaves
  // a value-equal `dir` untouched, so typing a filename prefix in the final
  // segment changes only `frag` (and re-caches `matches` cheaply from the
  // existing `entries`) instead of re-running the effect, wiping `entries`,
  // and flashing a transient "Listing…" on every keystroke.
  let dir = $derived.by(() => {
    const ix = query.lastIndexOf("/");
    return ix === -1 ? "" : query.slice(0, ix + 1);
  });
  let frag = $derived(query.slice(dir.length));

  // Seed the query from the `seed` prop on mount — read inside the effect rather
  // than the initializer so the reactive prop stays a real dependency and the
  // `state_referenced_locally` lint doesn't flag an initial-value capture.
  // Declared before the listing effect below so the first fetch uses the seeded
  // directory; the overlay remounts on every open, so this sets query once.
  $effect(() => {
    query = seed;
  });

  // Fetch only when the *directory* changes; the fragment filters
  // locally. Dropping the stale listing up front keeps the previous
  // folder's rows from flashing in while the new one loads.  The
  // cleanup clears the debounce timer and aborts any in-flight fetch,
  // so rapid typing issues at most one settled request; fetch_seq also
  // guards against an older response arriving out of order.
  let fetch_seq = 0;
  $effect(() => {
    const d = dir;
    const id = ++fetch_seq;
    const controller = new AbortController();
    entries = [];
    error = "";
    listing = true;
    const t = setTimeout(async () => {
      try {
        const url = new URL("/fs/list", window.location.href);
        url.searchParams.set("path", d === "" ? "." : d);
        const resp = await fetch(url, { signal: controller.signal });
        const data: any = await resp.json().catch(() => null);
        if (id !== fetch_seq) return; // stale — a newer listing won
        if (!resp.ok || data == null || !Array.isArray(data.dirs)) {
          error =
            (data && data.error ? data.error : "unexpected response") +
            ` (HTTP ${resp.status})`;
        } else {
          // Dirs first (the server sorts each group), then files.
          entries = [
            ...(data.dirs as string[]).map((name) => ({
              name,
              is_dir: true,
            })),
            ...(data.files as { name: string; type: string }[]).map((f) => ({
              name: f.name,
              is_dir: false,
              type: f.type,
            })),
          ];
          listed_dir = typeof data.path === "string" ? data.path : d;
        }
      } catch (e) {
        if (id === fetch_seq && !controller.signal.aborted) {
          error = String(e);
        }
      } finally {
        if (id === fetch_seq) listing = false;
      }
    }, DEBOUNCE_MS);
    return () => {
      clearTimeout(t);
      controller.abort();
    };
  });

  // Case-insensitive substring over entry names (the server's sorted
  // order — dirs first, then files — is preserved).  Capped so a giant
  // folder stays navigable.
  let matches = $derived.by(() => {
    const q = frag.toLowerCase();
    const m = q
      ? entries.filter((e) => e.name.toLowerCase().includes(q))
      : entries;
    return m.slice(0, MAX_RESULTS);
  });

  // Keep the highlight in range when the list shrinks (the filter
  // narrowing, or a stale response being dropped).
  $effect(() => {
    if (sel >= matches.length) sel = Math.max(0, matches.length - 1);
  });

  $effect(() => {
    void frag;
    sel = 0;
  });

  // Keep the highlighted row visible while navigating the capped list.
  $effect(() => {
    items[sel]?.scrollIntoView({ block: "nearest" });
  });

  // Autofocus on mount (the overlay wrapper is only mounted while the
  // picker is open).
  $effect(() => {
    input?.focus();
  });

  // Compose the full path for an entry: the typed directory prefix
  // (preserving relative/absolute form and any "./" styling) plus the
  // name.  Directories get a trailing "/" so a descent is a natural
  // continuation of the typed path.
  function path_for(entry: FsEntry): string {
    return entry.is_dir ? `${dir}${entry.name}/` : `${dir}${entry.name}`;
  }

  // Accept and insert an entry (file or folder) into the promptbar.
  function accept(entry: FsEntry | null) {
    if (!entry) {
      if (query.trim() !== "") onselect(query);
      else onselect(null);
      return;
    }
    onselect(path_for(entry));
  }

  // Descend into a directory (growing the typed path so the listing
  // follows), or accept a file.
  function complete_or_descend(entry: FsEntry | null) {
    if (!entry) return;
    if (entry.is_dir) {
      query = path_for(entry);
    } else {
      onselect(path_for(entry));
    }
  }

  // The needle for highlighting the matched portion of each name
  // (case-insensitive substring).  Mirrors HistorySearch/MacroPicker.
  let q = $derived(frag.toLowerCase());

  function on_key(event: KeyboardEvent) {
    if (event.isComposing || event.keyCode === 229) return;
    // ⌘F/Ctrl+F while the picker is open just closes it (never trigger
    // the browser's "find" bar).
    if (
      (event.ctrlKey || event.metaKey) &&
      event.key.toLowerCase() === "f" &&
      !event.shiftKey
    ) {
      event.preventDefault();
      onselect(null);
      return;
    }
    if (event.key === "Enter") {
      event.preventDefault(); // pick, do NOT submit a prompt
      accept(matches[sel] ?? null);
    } else if (event.key === "Tab" && !event.shiftKey) {
      event.preventDefault();
      complete_or_descend(matches[sel] ?? null);
    } else if (event.key === "ArrowDown") {
      event.preventDefault();
      if (matches.length) {
        sel = (sel + 1) % matches.length;
      }
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      if (matches.length) {
        sel = (sel - 1 + matches.length) % matches.length;
      }
    } else if (event.key === "Escape") {
      event.preventDefault();
      onselect(null);
    }
  }

  // Clicking/tapping outside the panel dismisses it without changing
  // the draft.  pointerdown on a row fires before this blur, so row
  // picks land first and close normally.
  function on_blur(event: FocusEvent) {
    if (
      panel_root &&
      event.relatedTarget !== null &&
      !panel_root.contains(event.relatedTarget as Node)
    ) {
      onselect(null);
    }
  }
</script>

<!-- Self-contained Spotlight-style card: positioned by the overlay
     wrapper in Promptbar, so it carries its own full chrome. -->
<div
  bind:this={panel_root}
  role="presentation"
  onmousedown={(e) => {
    if (e.target !== input) e.preventDefault();
  }}
  class="w-full max-w-xl rounded-xl border border-base-content/20 bg-base-100 shadow-2xl"
>
  <div class="flex items-center gap-2.5 px-4 pt-3 pb-1.5 text-sm">
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      class="w-4 h-4 shrink-0 text-base-content/40"
      aria-hidden="true"
    >
      <path
        d="M4 20h16a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"
      />
    </svg>
    <input
      bind:this={input}
      bind:value={query}
      onkeydown={on_key}
      onblur={on_blur}
      class="flex-1 bg-transparent focus:outline-none font-mono text-[0.85em] text-base-content placeholder:text-base-content/50"
      placeholder="Type a path… (e.g. src/main.cr)"
      aria-label="Browse a file path"
      autocomplete="off"
      autocorrect="off"
      autocapitalize="off"
      spellcheck="false"
    />
    <span
      class="text-xs text-base-content/65 select-none shrink-0"
      title="matched / entries in this folder"
    >
      {matches.length} / {entries.length}
    </span>
  </div>
  {#if error}
    <div class="px-4 pb-2.5 text-sm text-error/80">
      Can't list {dir || "."}: {error}
    </div>
  {:else if matches.length}
    <ul class="px-1.5 pb-1.5 max-h-64 overflow-y-auto" role="listbox">
      {#each matches as entry, i (entry.name + (entry.is_dir ? "/" : ""))}
        <li
          bind:this={items[i]}
          class="flex items-center gap-1 rounded-lg transition-colors {i === sel
            ? 'bg-accent/15 text-base-content'
            : 'text-base-content/75'}"
        >
          <!-- mousedown preventDefault keeps the input focused (a row
               pick on a directory re-lists and must stay keyboard-driven). -->
          <button
            type="button"
            title={path_for(entry) +
              (entry.is_dir
                ? " (click or Tab to open folder)"
                : entry.type
                  ? ` (${entry.type})`
                  : "")}
            onpointerdown={() => complete_or_descend(entry)}
            onmousedown={(e) => e.preventDefault()}
            class="flex-1 min-w-0 text-left px-2.5 py-1.5 rounded-lg flex items-center gap-2 text-sm"
          >
            {#if entry.is_dir}
              <svg
                xmlns="http://www.w3.org/2000/svg"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
                class="w-4 h-4 shrink-0 text-accent/60"
                aria-hidden="true"
              >
                <path
                  d="M4 20h16a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"
                />
              </svg>
            {:else}
              <svg
                xmlns="http://www.w3.org/2000/svg"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
                class="w-4 h-4 shrink-0 text-base-content/40"
                aria-hidden="true"
              >
                <path
                  d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"
                />
                <path d="M14 2v4a2 2 0 0 0 2 2h4" />
              </svg>
            {/if}
            <span class="truncate font-mono text-[0.9em]">
              {#each segments(entry.name, q) as seg}
                {#if seg.hit}
                  <mark class="bg-warning/25 text-inherit rounded-xs"
                    >{seg.text}</mark
                  >
                {:else}
                  {seg.text}
                {/if}
              {/each}
              {#if entry.is_dir}/{/if}
            </span>
            {#if entry.type && !entry.is_dir && entry.type !== "regular file"}
              <span
                class="ml-auto shrink-0 text-[0.62rem] uppercase tracking-wider text-base-content/40 bg-base-300/60 rounded px-1.5 py-0.5 font-medium"
                >{entry.type}</span
              >
            {/if}
          </button>
          {#if entry.is_dir}
            <button
              type="button"
              title="Insert folder {path_for(entry)} (Enter)"
              onpointerdown={() => accept(entry)}
              onmousedown={(e) => e.preventDefault()}
              class="shrink-0 mr-1.5 px-2 py-0.5 rounded text-xs text-base-content/65 hover:text-base-content hover:bg-base-300/70 transition-colors"
            >
              Insert
            </button>
          {/if}
        </li>
      {/each}
    </ul>
    {#if matches.length < entries.length}
      <div class="px-4 pb-1.5 text-xs text-base-content/65">
        {entries.length - matches.length} more in this folder — type more of the
        path to narrow
      </div>
    {/if}
  {:else if listing}
    <div class="px-4 pb-2.5 text-sm text-base-content/65">
      Listing {dir || "."}…
    </div>
  {:else}
    <div class="px-4 pb-2.5 text-sm text-base-content/65">
      No matching files
    </div>
  {/if}
  <div
    class="flex items-center gap-3 px-4 py-2 border-t border-base-content/15 text-xs text-base-content/70 select-none"
  >
    <span class="font-mono truncate" title={listed_dir || dir || "."}>
      browsing {listed_dir || dir || "."}
    </span>
    <span class="ml-auto shrink-0">&uarr;&darr; to navigate</span>
    <span class="shrink-0">Tab opens folder</span>
    <span class="shrink-0">Enter inserts</span>
    <span class="shrink-0">Esc to close</span>
  </div>
</div>
