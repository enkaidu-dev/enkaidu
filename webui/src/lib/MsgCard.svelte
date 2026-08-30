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
  class="indicator w-7/8 py-0 place-self-start text-sm text-base-content/65"
>
     {#if data[0].content}
       <details class="group/msg">
         <summary
          class="cursor-pointer list-none py-0 text-xs text-base-content/50 hover:text-base-content/70 transition-colors select-none flex items-center gap-1"
            >
            <span
            class="text-base-content/30 group-open/msg:rotate-90 transition-transform text-[0.85em] leading-none"
             >▶</span
           >
           <MsgLevel {level} />{data[0].subject}
         </summary>
         <div class="mt-1 text-xs text-base-content/55">
           {#if data.length > 0}
             <!-- Multiple data lines, so gather then all together -->
             {#each data as msg}
               {#if msg.content}
                 <Markdown
                content={msg.content}
                add_class="text-sm ms-2 ps-2"
                />
               {:else if msg != data[0]}
                 <div
                class="text-xs ms-2 ps-2 text-base-content/50"
                 >
                   {msg.subject}
                 </div>
               {/if}
             {/each}
           {:else}
             <!--  Single data line -->
             <div class="py-0 text-xs">
               <Markdown
              content={data[0].content}
              add_class="text-sm ms-2 ps-2 text-base-content/55"
              />
             </div>
           {/if}
         </div>
        </details>
    {:else}
        <!-- Single subject only, no body -->
        <div class="py-2 text-xs text-base-content/50">
          <MsgLevel {level} />{data[0].subject}
        </div>
     {/if}
</div>
