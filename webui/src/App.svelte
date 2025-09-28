<script lang="ts">
  import * as Acp from "./acp_schema_types";

  import { enkaidu_post_request, enkaidu_get_request } from "./utilities";

  import Menubar from "./lib/Menubar.svelte";
  import Promptbar from "./lib/Promptbar.svelte";
  import Session from "./lib/Session.svelte";
  // import Sidebar from "./lib/Sidebar.svelte";

  let session: Session;
  let prompt: Promptbar;

  let started = false;
  let handling_request = false;

  async function read_line_by_line(
    response: Response,
    handler: (line: string | null) => void,
  ) {
    const reader = response.body?.getReader();
    if (!reader) return;

    const decoder = new TextDecoder();
    let buffer = "";

    while (true) {
      let { done, value } = await reader.read();
      if (done) {
        // Process any remaining buffer
        if (buffer) handler(buffer);
        handler(null); // null to indicate no more lines
        break;
      }
      buffer += decoder.decode(value, { stream: true });
      let lines = buffer.split("\n");
      buffer = lines.pop() || ""; // Keep the last incomplete line in the buffer
      lines.forEach((line) => handler(line));
    }
  }

  function new_prompt_request(prompt: string): Acp.PromptRequest {
    return {
      sessionId: session.get_id(),
      prompt: [
        {
          type: "text",
          text: prompt,
        },
      ],
    };
  }

  async function handle_response(resp: Response) {
    // Use to track when in think mode while gathering text fragments.
    let text_thinking = false;

    await read_line_by_line(resp, function (line) {
      if (line != null) {
        let msg = JSON.parse(line);
        switch (msg.type) {
          case "message":
            session.add_event({
              type: `message_${msg.level}`,
              subject: msg.message,
              content: msg.details,
            });
            break;
          case "query":
            session.add_event({
              type: msg.prompt.startsWith("/") ? "command" : "query",
              content: msg.prompt,
            });
            break;
          case "llm_text":
            let content = msg.content.trim();
            let think_ix = content.indexOf("</think>");
            // Split think block if present
            if (think_ix > 0) {
              let think = content.substring(0, think_ix + 8).trim();
              if (think.length > 0) {
                session.add_event({ type: "think", content: think });
              }
              content = content.substring(think_ix + 8).trim();
            }
            if (content.length > 0) {
              session.add_event({ type: "llm", content: content });
            }
            break;
          case "llm_text_fragment":
            let fragment = msg.fragment.trim();
            if (fragment == "<think>") text_thinking = true;
            if (fragment.length > 0 || msg.fragment.includes("\n")) {
              session.add_event({
                type: text_thinking ? "think" : "llm",
                content: msg.fragment,
              });
            }
            if (fragment == "</think>") text_thinking = false;
            break;
          case "llm_tool_call":
            session.add_event({
              type: `message_success`,
              subject: `CALL "${msg.name}" with`,
              content: "`" + msg.args + "`",
            });
            break;
          case "shell_confirmation":
            session.show_confirmation(msg.command, msg.id);
            break;
          case "session_reset":
            session.reset();
            break;
        }
      }
    });
  }

  async function check_if_started() {
    if (!started) {
      let resp = await enkaidu_get_request("start");
      await handle_response(resp);
      started = true;
    }
  }

  async function on_prompt_ask(query: string) {
    try {
      handling_request = true;
      await check_if_started();

      query = query.trim();
      session.add_event({
        type: query.startsWith("/") ? "command" : "query",
        content: query,
      });
      let resp = await enkaidu_post_request(
        "prompt",
        new_prompt_request(query),
      );
      await handle_response(resp);
    } catch (error) {
      session.add_event({
        type: "message_error",
        subject: error as string,
      });
    } finally {
      handling_request = false;
      setTimeout(() => {
        prompt.focus();
      }, 10);
    }
  }
</script>

<main>
  <div class="drawer drawer-end">
    <input id="my-drawer" type="checkbox" class="drawer-toggle" />
    <div class="drawer-content">
      <div class="flex flex-col h-screen justify-between">
        <Menubar />
        <Session bind:this={session} />
        <Promptbar
          bind:this={prompt}
          onask={on_prompt_ask}
          loading={handling_request}
        />
      </div>
    </div>
    <!-- <Sidebar /> -->
  </div>
</main>
