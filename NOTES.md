# NOTES

## TODO

- [ ] Write test specs
- [ ] Document the code classes (viz. fix `ops lint` warnings)
- [ ] Figure out `curl` and `bash` installation script
- [x] Support "including" text and image files in queries, especially for vision models
- [x] Setup GH action to build Linux and macOS binaries
- [x] Support configuring MCP servers in config YAML file
- [x] Support session auto-loading of specific MCP servers
- [x] Add a tool to save an image where the provided image is in the `data:` base-64-encoded form
- [x] Does OpenAI protocol support input/output schema? The `parameters` value is a JSON schema (i.e. input), but non

### MCPC

- [ ] Figure out how to support oAuth2 based authorization
- [ ] Detect when MCP connection needs to be reset; there are some rules for this.
- [ ] Find a canonical server to run locally to test the protocol better
- [x] Organize built-in tools into toolsets and allow loading / autoloading / unloading of toolsets
- [x] Figure out how to improve MCP transport responsiveness. The MCP Inspector seems be deal with HTTP streaming much more responsively. My implementation, which needs `io.skip_to_end` after handling every response, seems sluggish.
- [x] Support more complex JSON schema for tool properties to support some MCP servers (e.g. Pixel Lab)
- [x] Support optional transport type when using MCP servers, to choose between `auto`, `legacy`, and `http`.
- [x] Support the deprecated SSE transport 'cuz there are so many servers out there.
- [x] Support MCP server authentication using bearer token

## MCP Support

Now supports legacy (deprecated) SSE over dual-http connections as well as the modern HTTP streaming. Also support non-streaming HTTP but I haven't found a good server to test this.

### Some MCP servers with tools

Server | Type | Status | Comment
-----|-----|-----|-----
https://remote.mcpservers.org/fetch/mcp | Modern | Works |
https://echo.mcp.inevitable.fyi/mcp | Modern | Works |
https://time.mcp.inevitable.fyi/mcp | Modern | Works | Slow, but no problems in a while
https://gitmcp.io/ANYGITHUBUSER/REPO | Modern | Works | Can be used with any  Github repo ... cool!
https://gitmcp.io/nickthecook/ops | Modern | Works | Provides MCP tools for that repo. Amazing.
https://mcp.llmtxt.dev/sse | Legacy (SSE) | Works | Can retrieve `llms.txt` for domains
https://mcp.semgrep.ai/sse | Legacy (SSE) | Works | Full JSON schema support works
https://huggingface.co/mcp | Modern |Works | (I had the wrong URL before.)

## Future

These are major changes I'd like to make to Enkaidu


### Build container image to run `enkaidu` with safe shell access

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

### Web interface

Consider [Kemal](https://github.com/kemalcr/kemal) to support a built-in web UI that mimics the CLI.

And use [BakedFileSystem](https://github.com/ralsina/baked_file_system) to bundle the static file in the binary.

And [Svelte](https://svelte.dev/docs/svelte/overview) with TypeScript (of course!) would be nice to write the web UI since it can be used to produce a SPA that can be "baked" into the binary.

### Support prompts via MCP

MCP supports prompts as a service type for MCP servers. This is a good way to allow an MCP server to provide specific prompts based on inputs for querying an AI model. Especially when tool calls themselves produce non-trivial data.

References

- https://modelcontextprotocol.io/specification/2025-03-26/server/prompts

### Image generation via MCP

Some image generation services offer MCP servers. It would be cool to be able to use them when working on games.

https://modelcontextprotocol.io/specification/2025-06-18/schema#calltoolresult

- [ ] Support the `Image` content type.
- [x] Support image file saving given `Image` content type so we can save generated images

Known MCP servers:
- Pixel Lab (`https://api.pixellab.ai/mcp`)

### Distributing `enkaidu`

Build releases via Github for Linux and macOS.

Regarding signing / quarantining, see [this answer in SO](https://stackoverflow.com/questions/67446317/why-are-executables-installed-with-homebrew-trusted-on-macos):

> There is no quarantining flag for a CLI app downloaded with curl. Home-brew, uses UNIX core tools to download the bottles, and thus they don't have this flag set.

So providing instructions to fetch / install via `curl` should provide an interim solution.

## Done

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

References

- https://platform.openai.com/docs/guides/images-vision?api-mode=responses&format=base64-encoded
