<script lang="ts">
  import * as Common from "../common_types";
  import Markdown from "./Markdown.svelte";

  let {
    onconfirm,
    description,
    subjects,
    banner,
    id,
    show = true,
  }: Common.SecurityConfirmDialogConfig & {
    onconfirm: Common.SecurityConfirmSubmit;
  } = $props();

  // Present each subject as its own fenced code block (they are shell
  // commands, possibly several). Rendering through the shared Markdown
  // pipeline gives us syntax highlighting and the hover copy chip for
  // free. One fence per subject keeps each command visually distinct.
  let subjects_markdown = $derived(
    subjects.map((subject) => "```bash\n" + subject + "\n```").join("\n\n"),
  );

  function handleApprove() {
    onconfirm(id, true);
  }

  function handleDeny() {
    onconfirm(id, false);
  }
</script>

{#if show}
  <div class="modal modal-open">
    <div class="modal-box max-w-2xl">
      <h3 class="font-bold text-lg text-warning">
        ⚠️ Security-related Confirmation Required
      </h3>
      <div class="py-4">
        {#if banner}
          <p class="mb-3 font-medium {banner.safe ? "text-success" : "text-error"}">
            {banner.message}
          </p>
        {/if}
        <p class="mb-4">
          {description}
        </p>
        {#if subjects.length > 0}
          <Markdown content={subjects_markdown} add_class="my-0" />
        {/if}
        <p class="mt-4 text-sm text-base-content/70">
          Please review carefully before proceeding. Security confirmations are
          for operations that could adversely affect your system running
          Enkaidu.
        </p>
      </div>
      <div class="modal-action">
        <button class="btn btn-error" onclick={handleDeny}>
          <svg
            class="w-4 h-4"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M6 18L18 6M6 6l12 12"
            ></path>
          </svg>
          Deny
        </button>
        <button class="btn btn-success" onclick={handleApprove}>
          <svg
            class="w-4 h-4"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M5 13l4 4L19 7"
            ></path>
          </svg>
          Allow
        </button>
      </div>
    </div>
    <div class="modal-backdrop opacity-50"></div>
  </div>
{/if}
