<script lang="ts">
  import * as Acp from "./acp_schema_types";

  import Menubar from "./lib/Menubar.svelte";
  import Promptbar from "./lib/Promptbar.svelte";
  import Session from "./lib/Session.svelte";
  import Sidebar from "./lib/Sidebar.svelte";

  let session: Session;

  function read_line_by_line(
    response: Response,
    handler: (line: string | null) => void,
  ) {
    const reader = response.body?.getReader();
    const decoder = new TextDecoder();
    let buffer = "";

    function read() {
      reader?.read().then(({ done, value }) => {
        if (done) {
          // Process any remaining buffer
          if (buffer) {
            handler(buffer);
          }
          handler(null); // null to indicate no more lines
          return;
        }
        buffer += decoder.decode(value, { stream: true });
        let lines = buffer.split("\n");
        buffer = lines.pop() || ""; // Keep the last incomplete line in the buffer
        lines.forEach((line) => handler(line));
        read(); // Read the next chunk
      });
    }

    read(); // Start reading
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

  async function on_prompt_ask(query: string) {
    session.add_event({
      type: "query",
      content: query,
    });
    let resp = await post_request("prompt", new_prompt_request(query));
    let last_type: string | null = null;
    let text_aggr = "";
    read_line_by_line(resp, function (line) {
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
          session.add_event({ type: "llm", content: text_aggr });
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
          case "llm_text":
            session.add_event({ type: "llm", content: msg.content });
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
