<script lang="ts">
  import Markdown from "./Markdown.svelte";

  type MessageData = {
    subject?: string | undefined;
    content?: string | undefined;
  };

  let { level, data }: { level: string; data: MessageData[] } = $props();
</script>

<div
  class="indicator w-7/8 p-1 card card-xs shadow-sm place-self-start bg-base-100 text-sm text-base-content dark:border-base-content dark:border-1 dark:border-dashed"
>
  {#if level == "warn"}
    <span class="indicator-item badge badge-sm badge-warning">WARN</span>
  {:else if level == "success"}
    <span class="indicator-item badge badge-sm badge-success">OK</span>
  {:else if level == "error"}
    <span class="indicator-item badge badge-sm badge-error">ERROR</span>
  {:else if level == "info"}
    <span class="indicator-item badge badge-sm badge-info">INFO</span>
  {:else}
    <span class="indicator-item badge badge-sm badge-error"
      >{`?(${level})?`}</span
    >
  {/if}
  {#each data as msg}
    {#if msg.content}
      <div class="collapse collapse-arrow">
        <input type="checkbox" />
        <div class="collapse-title card-title text-xs">
          {msg.subject}
        </div>
        <div class="collapse-content text-xs">
          <Markdown content={msg.content} add_class="text-sm" />
        </div>
      </div>
    {:else}
      <p>{msg.subject}</p>
    {/if}
  {/each}
</div>
