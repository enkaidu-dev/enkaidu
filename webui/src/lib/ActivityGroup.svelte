<script lang="ts">
  import AsstThinkCard from "./AsstThinkCard.svelte";
  import ToolCallCard from "./ToolCallCard.svelte";
  import MsgCard from "./MsgCard.svelte";

  type SessionData = { subject?: string; content?: string };
  type SessionEntry = { type: string; data: SessionData[] };

  let { items, active = false }: { items: SessionEntry[]; active?: boolean } =
    $props();

  let isOpen = $state(false);

  function toggle(e: Event) {
    e.preventDefault();
    isOpen = !isOpen;
  }

  function truncate(s: string, max: number): string {
    return s.length > max ? s.slice(0, max).trimEnd() + "…" : s;
  }

  // Title reflects the most recent item in the group. Updates live as new
  // items are appended (the derived re-runs when items changes).
  let title = $derived.by(() => {
    const last = items.at(-1);
    if (!last) return "Working…";
    const d = last.data[0];
    if (!d) return "Working…";

    if (last.type === "tool_call") {
      // Prefer the LLM-supplied `reason` over the tool name.
      try {
        const parsed: unknown = JSON.parse(d.content || "{}");
        if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
          const r = (parsed as Record<string, unknown>)["reason"];
          if (typeof r === "string" && r.trim()) return truncate(r, 60);
        }
      } catch {
        /* fall through to name */
      }
      return d.subject || "Tool call";
    }

    const text = (d.content || "").trim();
    if (!text) return "Thinking…";
    return truncate(text, 60);
  });

  const count = $derived(items.length);
</script>

<div class="w-7/8 place-self-start">
  <details class="group/act" open={isOpen}>
    <summary
      class="list-none py-0 text-xs cursor-pointer select-none transition-colors flex items-center gap-1.5
        text-base-content/40 hover:text-base-content/55"
      onclick={toggle}
    >
      {#if active}
        <span class="activity-dot" aria-hidden="true"></span>
      {:else}
        <span
          class="text-base-content/30 group-open/act:rotate-90 transition-transform text-[0.85em] leading-none"
          >▶</span
        >
      {/if}
      <span class="font-medium">{title}</span>
      <span class="text-base-content/30"
        >{count} {count === 1 ? "step" : "steps"}</span
      >
    </summary>

    {#if isOpen}
      <div
        class="space-y-4 mt-3 border-l-2 border-base-content/8 pl-3"
      >
        {#each items as item, ii (ii)}
          {#if item.type === "llm_think"}
            <AsstThinkCard
              message={item.data[0]?.content || ""}
              active={false}
            />
          {:else if item.type === "tool_call"}
            <ToolCallCard
              name={item.data[0]?.subject || "tool"}
              args={item.data[0]?.content || "{}"}
            />
          {:else if item.type.startsWith("message_")}
            <MsgCard
              level={item.type.split("_").at(-1) || "info"}
              data={item.data}
            />
          {/if}
        {/each}
      </div>
    {/if}
  </details>
</div>
