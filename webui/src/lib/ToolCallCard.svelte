<script lang="ts">
  let { name, args }: { name: string; args: string } = $props();

  // Parse the tool's argument JSON once so we can (a) lift the optional
  // `reason` field to use as the card title and (b) pretty-print the remaining
  // parameters for the body. Degrades to the raw string if parsing fails.
  let parsed: Record<string, unknown> | null = $derived.by(() => {
    try {
      const value: unknown = JSON.parse(args);
      return value && typeof value === "object"
        ? (value as Record<string, unknown>)
        : null;
    } catch {
      return null;
    }
  });

  // The LLM-supplied reason, when present. This stands in for the "Thinking"
  // headline of AsstThinkCard — the tool call explains *why* it ran.
  let reason = $derived(
    parsed && typeof parsed.reason === "string" ? parsed.reason : "",
  );

  // Title: the reason when we have one, else fall back to the tool name.
  let title = $derived(reason.trim() ? reason : name);

  // Keep the tool name visible (as a trailing token) whenever a reason is the
  // headline and it differs from the name — otherwise we'd lose which tool ran.
  let show_name = $derived(!!reason.trim() && reason !== name);

  // Body: pretty-printed JSON of the parameters. The `reason` key is lifted to
  // the title (mirroring the console renderer) so it isn't shown twice.
  let body = $derived.by(() => {
    if (!parsed) return args;
    const params = { ...parsed };
    delete params.reason;
    return JSON.stringify(params, null, 2);
  });
</script>

<div class="w-7/8 place-self-start text-base-content/50">
  <details class="group/tool">
    <summary
      class="cursor-pointer list-none py-0 text-xs font-medium text-base-content/40 hover:text-base-content/60 transition-colors select-none flex items-center gap-1"
    >
      <span
        class="text-base-content/30 group-open/tool:rotate-90 transition-transform text-[0.85em] leading-none"
        >▶</span
      >
      <span>{title}</span>
      {#if show_name}
        <span class="text-base-content/30">· {name}</span>
      {/if}
    </summary>
    <div class="ms-5 ps-2 mt-1 max-h-40 overflow-y-auto text-base-content/60">
      <pre
        class="text-xs font-mono whitespace-pre-wrap break-words m-0 select-text"
      >{body}</pre>
    </div>
  </details>
</div>
