# NOTES

## TODO

- [ ] Write test specs
- [ ] Document the code classes (viz. fix `ops lint` warnings)
- [ ] Add a tool to save an image where the provided image is in the `data:` base-64-encoded form

### MCPC

- [ ] Figure out how to support oAuth2 based authorization
- [ ] Detect when MCP connection needs to be reset; there are some rules for this.
- [ ] Find a canonical server to run locally to test the protocol better
- [ ] Figure out how to improve MCP transport responsiveness. The MCP Inspector seems be deal with HTTP streaming much more responsively. My implementation, which needs `io.skip_to_end` after handling every response, seems sluggish.
- [ ] Support more complex tool JSON schema for complex objects etc.
- [x] Support the deprecated SSE transport 'cuz there are so many servers out there.
- [x] Support MCP server authentication using bearer token

## MCP Support

Now supports legacy (deprecated) SSE over dual-http connections as well as the modern HTTP streaming. Also support non-streaming HTTP but I haven't found a good server to test this.

### Some MCP servers with tools

Server | Type | Comment
-----|-----|-----
https://remote.mcpservers.org/fetch/mcp | Modern | Works
https://echo.mcp.inevitable.fyi/mcp | Modern | Works
https://time.mcp.inevitable.fyi/mcp | Modern | Works; occasionally fails but I think this is a server problem
https://gitmcp.io/ANYGITHUBUSER/REPO | Modern | Works for any Github repo
https://gitmcp.io/nickthecook/ops | Modern | Provides MCP tools for that repo. Amazing.
https://mcp.llmtxt.dev/sse | Legacy (SSE) | Can retrieve `llms.txt` for domains
https://hf.co/mcp | Modern | Doesn't work; uses HTTP but not streaming
https://mcp.semgrep.ai/sse | Legacy (SSE) | Partially works; has complex JSON schema which we don't support yet

## Future

These are major changes I'd like to make to Enkaidu

### Safe shell access

It would be great to support shell access so that the model can be used to run tests and review results as part of supporting coding.

To do this I really want to have some kind of OS-level guardrails to ensure scripts can't break out of a "jail" to modify / access stuff they shouldn't.

Think ...

- Consider [chroot](https://en.wikipedia.org/wiki/Chroot) jails
- But these can be a pain to setup
- Containers are perfect for this, with volume mounting to just the bits we want; but now we need to include `docker` or `podman` with the app!
- What else?

### Web interface

Consider [Kemal](https://github.com/kemalcr/kemal) to support a built-in web UI that mimics the CLI.

And use [BakedFileSystem](https://github.com/ralsina/baked_file_system) to bundle the static file in the binary.

And [Svelte](https://svelte.dev/docs/svelte/overview) with TypeScript (of course!) would be nice to write the web UI since it can be used to produce a SPA that can be "baked" into the binary.

### Image generation

Some image generation services offer MCP servers. It would be cool to be able to use them when working on games.

https://modelcontextprotocol.io/specification/2025-06-18/schema#calltoolresult

- Support the `Image` content type.
- Support image file saving given `Image` content type so we can save generated images

Known MCP servers:
- Pixel Lab (`https://api.pixellab.ai/mcp`)

### Complete [JSON Schema](https://json-schema.org/docs) support

When listing tools, the too definition has more than just simple parameter types: https://modelcontextprotocol.io/specification/2025-06-18/schema#tool

Per `LLM::Function` (or do we need a derived `MCP::Function`?)
- Support full JSON schema for input schema
- Add support for output schema
- Check out [json-schema](https://github.com/spider-gazelle/json-schema) shard

## Done

### Interactive reader (Done)

Using [REPLy](https://github.com/I3oris/reply/) shard (derived from the Crystal REPL support) which provides better editing, and gives us a framework for future enhancements (e.g. auto-completion, history etc.)

### Authentication for MCP servers (Done)

Many MCP servers behind paywalls support `Bearer Authentication`.

- Add ability to specify bearer auth
- Where / how do we specify the API key per server?

Questions
- [ ] Does OpenAI protocol support input/output schema?
