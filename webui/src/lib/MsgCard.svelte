<script lang="ts">
  import Markdown from "./Markdown.svelte";

  type MessageData = {
    subject?: string | undefined;
    content?: string | undefined;
  };

  let { level, data }: { level: string; data: MessageData[] } = $props();
</script>

<div
  class="indicator w-7/8 py-0 card card-xs shadow-sm place-self-start bg-base-200 text-sm text-base-content dark:border-base-content dark:border-1 dark:border-dashed"
>
  {#if level == "warn"}
    <span
      class="indicator-item indicator-center badge badge-sm badge-soft badge-warning"
      >WARN</span
    >
  {:else if level == "success"}
    <span
      class="indicator-item indicator-center badge badge-sm badge-soft badge-success"
      >OK</span
    >
  {:else if level == "error"}
    <span
      class="indicator-item indicator-center badge badge-sm badge-soft badge-error"
      >ERROR</span
    >
  {:else if level == "info"}
    <span
      class="indicator-item indicator-center badge badge-sm badge-soft badge-info"
      >INFO</span
    >
  {:else}
    <span
      class="indicator-item indicator-center badge badge-sm badge-soft badge-error"
      >{`?(${level})?`}</span
    >
  {/if}

  {#if data.length > 1}
    <div class="collapse py-0 collapse-arrow">
      <input type="checkbox" />
      <div class="collapse-title py-0 card-title text-xs">
        {data[0].subject}
      </div>
      <div class="collapse-content py-0 text-xs">
        {#each data as msg}
          {#if msg.content}
            <Markdown content={msg.content} add_class="text-sm pl-5" />
          {:else if msg != data[0]}
            <div class="card-title text-xs">
              {msg.subject}
            </div>
          {/if}
        {/each}
      </div>
    </div>
  {:else}
    <div class="card-title py-2 ps-4 text-xs">
      {data[0].subject}
    </div>
  {/if}
</div>
