<script lang="ts">
  // Spotlight-style file browser for the Promptbar's ⌘F/Ctrl+F overlay.
  // The user types a path fragment: the *directory* part (everything up
  // to and including the last "/") is listed from the server via
  // GET /fs/list?path=… (relative paths resolve against the server's
  // working directory; paths outside it come back as 403), and the
  // remainder is a local case-insensitive filter over the listing — so
  // a fetch fires only when the directory part changes, never per
  // filtered keystroke.
  //
  // Enter on a *file* calls onselect with the composed path (the typed
  // directory prefix + the name, preserving relative/absolute form);
  // Enter on a *directory* descends into it instead, growing the typed
  // path — the terminal Tab-muscle-memory of walking `./` paths.  Esc,
  // ⌘F/Ctrl+F again, a backdrop click, or focus leaving the card all
  // dismiss via onselect(null) without touching the draft.
  // (Promptbar owns the overlay; this card is display + pointer + its own
  // keyboard/input, and reports results back through `onselect`.)
  let { onselect }: {
    onselect: (path: string | null) => void;
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

  // Split the typed path into (dir, frag): dir is everything up to and
  // including the last "/" ("" means the server's cwd), frag is the rest.
  // A space is a legal path character and stays part of the fragment.
  let parts = $derived.by(() => {
    const s = query;
    const ix = s.lastIndexOf("/");
    if (ix === -1) return { dir: "", frag: s };
    return { dir: s.slice(0, ix + 1), frag: s.slice(ix + 1) };
  });

  let frag = $derived(parts.frag);

  // Fetch only when the *directory* changes; the fragment filters
  // locally. Dropping the stale listing up front keeps the previous
  // folder's rows from flashing in while the new one loads.  The
  // cleanup clears the debounce timer, so rapid typing issues at most
  // one fetch per settled directory; fetch_seq guards against a slow
  // response from an older directory arriving last.
  let fetch_seq = 0;
  $effect(() => {
    const d = parts.dir;
    const id = ++fetch_seq;
    entries = [];
    error = "";
    listing = true;
    const t = setTimeout(async () => {
      try {
        const url = new URL("/fs/list", window.location.href);
        url.searchParams.set("path", d === "" ? "." : d);
        const resp = await fetch(url);
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
        if (id === fetch_seq) error = String(e);
      } finally {
        if (id === fetch_seq) listing = false;
      }
    }, DEBOUNCE_MS);
    return () => clearTimeout(t);
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

  // Like Spotlight, each keystroke re-anchors to the best (top) match.
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
    return entry.is_dir
      ? `${parts.dir}${entry.name}/`
      : `${parts.dir}${entry.name}`;
  }

  function select(entry: FsEntry | null) {
    if (!entry) {
      onselect(null);
      return;
    }
    if (entry.is_dir) {
      // Descend: grow the typed path (the fragment becomes empty, so
      // every entry of the folder is shown and the listing follows).
      query = path_for(entry);
    } else {
      onselect(path_for(entry));
    }
  }

  // The needle for highlighting the matched portion of each name
  // (case-insensitive substring).  Mirrors HistorySearch/MacroPicker.
  let q = $derived(frag.toLowerCase());
  type Segment = { text: string; hit: boolean };
  function segments(text: string, needle: string): Segment[] {
    if (!needle) return [{ text, hit: false }];
    const lower = text.toLowerCase();
    const out: Segment[] = [];
    let i = 0;
    let ix = lower.indexOf(needle);
    while (ix !== -1) {
      if (ix > i) out.push({ text: text.slice(i, ix), hit: false });
      out.push({ text: text.slice(ix, ix + needle.length), hit: true });
      i = ix + needle.length;
      ix = lower.indexOf(needle, i);
    }
    if (i < text.length) out.push({ text: text.slice(i), hit: false });
    return out;
  }

  function on_key(event: KeyboardEvent) {
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
      select(matches[sel] ?? null);
    } else if (event.key === "ArrowDown") {
      event.preventDefault();
      if (matches.length) sel = (sel + 1) % matches.length;
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      if (matches.length) sel = (sel - 1 + matches.length) % matches.length;
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
      class="flex-1 bg-transparent focus:outline-none font-mono text-[0.85em] text-base-content placeholder:text-base-content/30"
      placeholder="Type a path… (e.g. src/main.cr)"
      aria-label="Browse a file path"
      autocomplete="off"
      autocorrect="off"
      autocapitalize="off"
      spellcheck="false"
    />
    <span
      class="text-xs text-base-content/40 select-none"
      title="matched / entries in this folder"
    >
      {matches.length} / {entries.length}
      <span class="hidden sm:inline"> · Esc to close</span>
    </span>
  </div>
  {#if error}
    <div class="px-4 pb-2.5 text-sm text-error/80">
      Can't list {parts.dir || "."}: {error}
    </div>
  {:else if matches.length}
    <ul class="px-1.5 pb-1.5 max-h-64 overflow-y-auto" role="listbox">
      {#each matches as entry, i (entry.name + (entry.is_dir ? "/" : ""))}
        <li bind:this={items[i]}>
          <!-- mousedown preventDefault keeps the input focused (a row
               pick on a directory re-lists and must stay keyboard-driven). -->
          <button
            type="button"
            title={path_for(entry) +
              (entry.type && !entry.is_dir ? ` (${entry.type})` : "")}
            onpointerdown={() => select(entry)}
            onmousedown={(e) => e.preventDefault()}
            class="w-full text-left px-2.5 py-1.5 rounded-lg flex items-center gap-2 text-sm transition-colors {i ===
            sel
              ? 'bg-accent/15 text-base-content'
              : 'text-base-content/75'}"
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
        </li>
      {/each}
    </ul>
    {#if matches.length < entries.length}
      <div class="px-4 pb-1.5 text-xs text-base-content/40">
        {entries.length - matches.length} more in this folder — type more of the
        path to narrow
      </div>
    {/if}
  {:else if listing}
    <div class="px-4 pb-2.5 text-sm text-base-content/40">
      Listing {parts.dir || "."}…
    </div>
  {:else}
    <div class="px-4 pb-2.5 text-sm text-base-content/40">
      No matching files
    </div>
  {/if}
  <div
    class="flex items-center gap-3 px-3 py-1.5 border-t border-base-content/10 text-[0.7rem] text-base-content/30"
  >
    <span class="font-mono truncate" title={listed_dir || parts.dir || "."}>
      browsing {listed_dir || parts.dir || "."}
    </span>
    <span class="ml-auto shrink-0">&uarr;&darr; to navigate</span>
    <span class="shrink-0">Enter opens a folder / inserts a file</span>
    <span class="shrink-0">Esc to close</span>
  </div>
</div>
