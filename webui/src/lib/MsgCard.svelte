<script lang="ts">
  import Markdown from "./Markdown.svelte";
  import MsgLevel from "./MsgLevel.svelte";

  type MessageData = {
    subject?: string | undefined;
    content?: string | undefined;
  };

  let { level, data }: { level: string; data: MessageData[] } = $props();
</script>

<div
  class="indicator w-7/8 py-0 card card-xs shadow-none place-self-start bg-base-200 border-0 text-sm text-base-content"
  // class="indicator w-7/8 py-0 card card-xs shadow-sm place-self-start bg-base-200 text-sm text-base-content dark:border-base-content dark:border-1 dark:border-dashed"
>
  {#if data[0].content}
    <div class="collapse py-0 collapse-arrow">
      <input type="checkbox" />
      <div
        class="collapse-title card-title py-0 text-ghost text-xs after:inset-s-5 after:inset-e-auto pe-4 ps-10"
      >
        <MsgLevel {level} />{data[0].subject}
      </div>
      <div class="collapse-content py-0 text-xs">
        {#if data.length > 0}
          <!-- Multiple data lines, so gather then all together -->
          {#each data as msg}
            {#if msg.content}
              <Markdown
                content={msg.content}
                add_class="text-sm ms-2 ps-2 border-l-gray-400 border-l-2"
              />
            {:else if msg != data[0]}
              <div
                class="card-title text-xs ms-2 ps-2 border-l-gray-400 border-l-2"
              >
                {msg.subject}
              </div>
            {/if}
          {/each}
        {:else}
          <!--  Single data line -->
          <div class="collapse-content py-0 text-xs">
            <Markdown
              content={data[0].content}
              add_class="text-sm ms-2 ps-2 border-l-gray-400 border-l-2"
            />
          </div>
        {/if}
      </div>
    </div>
  {:else}
    <!-- Single subject only, no body -->
    <div class="card-title py-2 ps-4 text-xs">
      <MsgLevel {level} />{data[0].subject}
    </div>
  {/if}
</div>
