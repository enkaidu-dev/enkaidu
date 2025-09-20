<script lang="ts">
  import * as Acp from "./acp_schema_types";

  import Menubar from "./lib/Menubar.svelte";
  import Promptbar from "./lib/Promptbar.svelte";
  import Session from "./lib/Session.svelte";
  import Sidebar from "./lib/Sidebar.svelte";

  let session: Session;
  let started = false;

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

  async function get_request(path: string) {
    const request = new Request(`http://localhost:8765/api/${path}`, {
      method: "GET",
    });

    return await fetch(request);
  }

  async function post_request(path: string, content: any) {
    const headers = new Headers({
      "Content-Type": "application/json",
    });

    const request = new Request(`http://localhost:8765/api/${path}`, {
      method: "POST",
      body: JSON.stringify(content),
      headers: headers,
    });

    return await fetch(request);
  }

  async function handle_response(resp: Response) {
    let last_type: string | null = null;
    let text_aggr = "";
    await read_line_by_line(resp, function (line) {
      if (line == null) {
        // no more lines.
        if (last_type == "llm_text_fragment") {
          // gather up text content
          session.add_event({ type: "llm", content: text_aggr });
        }
      } else {
        let msg = JSON.parse(line);
        if (last_type != msg.type && last_type == "llm_text_fragment") {
          // gather up text content
          if (text_aggr.trim.length > 0) {
            session.add_event({ type: "llm", content: text_aggr });
          }
          text_aggr = "";
        }
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
            text_aggr += msg.fragment;
            if (msg.fragment == "</think>") {
              session.add_event({ type: "think", content: text_aggr });
              text_aggr = "";
              msg.type = "llm_text";
            }
            break;
          case "llm_tool_call":
            session.add_event({
              type: `message_info`,
              subject: `CALL "${msg.name}" with`,
              content: "`" + msg.args + "`",
            });
            break;
        }
        last_type = msg.type;
      }
    });
  }

  async function check_if_started() {
    if (!started) {
      let resp = await get_request("start");
      await handle_response(resp);
      started = true;
    }
  }

  async function on_prompt_ask(query: string) {
    await check_if_started();

    query = query.trim();
    session.add_event({
      type: query.startsWith("/") ? "command" : "query",
      content: query,
    });
    let resp = await post_request("prompt", new_prompt_request(query));
    await handle_response(resp);
  }
</script>

<main>
  <div class="drawer drawer-end">
    <input id="my-drawer" type="checkbox" class="drawer-toggle" />
    <div class="drawer-content">
      <div class="flex flex-col h-screen justify-between">
        <Menubar />
        <Session bind:this={session} />
        <Promptbar onask={on_prompt_ask} />
      </div>
    </div>
    <Sidebar />
  </div>
</main>
