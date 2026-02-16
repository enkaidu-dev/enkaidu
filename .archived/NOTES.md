# NOTES

> ARCHIVED FOR POSTERITY

I used this in the early days of building Enkaidu.

## Done

### Build container image to run `enkaidu` with safe shell access (Done)

> **WHY?**
>
> It would be great to support shell access so that the model can be used to run tests and review results as part of supporting coding.
>
> To do this I really want to have some kind of OS-level guardrails to ensure scripts can't break out of a "jail" to modify / access stuff they shouldn't.

A way to absolutely cut the risk of wider disk access, we could ship `enkaidu` as a container image that user can _execute_ with a volume-mount to the folder they want to work in.

E.g. containers starts in `/opt/workspace` and uer launches container and uses volume-mounting to map, e.g. `$HOME/Dev/project` to `/opt/workspace`. Then
- we could even block networking access for the container, and
- we could give more shell access.

Does this give us ZERO exfil / malware / host damage risk?

### Support prompts via MCP (Done)

MCP supports prompts as a service type for MCP servers. This is a good way to allow an MCP server to provide specific prompts based on inputs for querying an AI model. Especially when tool calls themselves produce non-trivial data.

References

- https://modelcontextprotocol.io/specification/2025-03-26/server/prompts

### Branch sessions (Done)

While configurable prompts can do a lot of useful work, complex prompts can result in a lot of intermediate actions that become part of the session context.

#### Forked session (Done)

Consider running prompts in a forked session (of current session) where the user can choose to bring the some or none of the output into the current session.

This could also be a way to run forked session using a different LLM / model, like summarizing the current session or doing some analysis with a different model.

#### Isolated sessions (Done)

Instead of forking, we could also run a bare session with a model to do some utility work; e.g. analyze an image (though some of this might be more useful as a tool call for the main session.)

### Web interface

Built it using Crystal's `HTTP::Server` API, defining a simple router in `src/sucre/web_server`.

Used [BakedFileSystem](https://github.com/ralsina/baked_file_system) to bundle the static file in the binary.

And [Svelte](https://svelte.dev/docs/svelte/overview) with TypeScript (of course!) would be nice to write the web UI since it can be used to produce a SPA that can be "baked" into the binary.

### Interactive reader (Done)

Using [REPLy](https://github.com/I3oris/reply/) shard (derived from the Crystal REPL support) which provides better editing, and gives us a framework for future enhancements (e.g. auto-completion, history etc.)

Notable:
- `Alt-Enter` or `Option-Enter` can be used to start multi-line query editing
- `Ctrl-R` can be used to search input history

### Authentication for MCP servers (Done)

Many MCP servers behind paywalls support `Bearer Authentication`.

- Add ability to specify bearer auth
- Where / how do we specify the API key per server?

### Complete [JSON Schema](https://json-schema.org/docs) support

When listing tools, the too definition has more than just simple parameter types: https://modelcontextprotocol.io/specification/2025-06-18/schema#tool

Per `LLM::Function` (or do we need a derived `MCP::Function`?)
- [x] Support full JSON schema for input schema
- [x] Check out [json-schema](https://github.com/spider-gazelle/json-schema) shard

### Group tools into toolsets (Done)

We have a lot of default tools and they fill up the query requests and thus the context. Some tools make sense all the time but not all do.

- [x] Define toolsets: e.g. "File management", "Image Files", "Date and Time", "Shell Commands" etc.
- [x] Group the tools in `src/tools` under modules so we can automagic the toolset definitions
- [x] Add `/toolset ls` command
- [x] Add `/toolset load NAME` command
- [x] Add `/toolset unload NAME` command
- [x] Add `autoload: { ... toolsets: [...]}` to the config

### Send image with a query

LLM models with vision capability can be sent image data as part of a query. Need a way to specify an image before a query _just_ for the query.

- Consider `/include image URL | FILEPATH` command that only affects the next query.
- This could be a pattern for sending other file-types? e.g. documents

### MCP Support

Now supports legacy (deprecated) SSE over dual-http connections as well as the modern HTTP streaming. Also support non-streaming HTTP but I haven't found a good server to test this.

#### Some MCP servers with tools

|Server                                 |Type        |Status|Comment                                    |
|---------------------------------------|------------|------|-------------------------------------------|
|https://remote.mcpservers.org/fetch/mcp|Modern      |Works |                                           |
|https://echo.mcp.inevitable.fyi/mcp    |Modern      |Works |                                           |
|https://time.mcp.inevitable.fyi/mcp    |Modern      |Works |Slow, but no problems in a while           |
|https://gitmcp.io/ANYGITHUBUSER/REPO   |Modern      |Works |Can be used with any  Github repo ... cool!|
|https://gitmcp.io/nickthecook/ops      |Modern      |Works |Provides MCP tools for that repo. Amazing. |
|https://mcp.llmtxt.dev/sse             |Legacy (SSE)|Works |Can retrieve `llms.txt` for domains        |
|https://mcp.semgrep.ai/sse             |Legacy (SSE)|Works |Full JSON schema support works             |
|https://huggingface.co/mcp             |Modern      |Works |(I had the wrong URL before.)              |

References

- https://platform.openai.com/docs/guides/images-vision?api-mode=responses&format=base64-encoded
