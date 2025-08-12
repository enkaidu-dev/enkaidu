# NOTES

## TODO

- [ ] Write test specs
- [ ] Document the code classes (viz. fix `ops lint` warnings)

### MCPC

- [ ] Figure out how to support authentication (a) oAuth2 per spec? (b) API key? (c) Basic auth over HTTPS?
- [ ] Detect when MCP connection needs to be reset; there are some rules for this.
- [ ] Find a canonical server to run locally to test the protocol better
- [ ] Figure out how to improve MCP transport responsiveness. The MCP Inspector seems be deal with HTTP streaming much more responsively. My implementation, which needs `io.skip_to_end` after handling every response, seems sluggish.
- [ ] Support the deprecated SSE transport 'cuz there are so many servers out there.

## MCP Support

Currently we only support HTTP + Streaming via POST method. Also support non-streaming HTTP but I haven't found a good server to test this. 

> FYI. We do not yet support the deprecated SSE transport.

### Some MCP servers with tools

#### https://remote.mcpservers.org/fetch/mcp

- Works

#### https://echo.mcp.inevitable.fyi/mcp

- Works

#### https://time.mcp.inevitable.fyi/mcp

- Works
- Occasionally fails but I think this is a server problem

#### https://gitmcp.io/ANYGITHUBUSER/REPO

E.g. `https://gitmcp.io/nickthecook/ops` provides MCP tools for that repo. Amazing.

- Works after a fix to support tools without parameters

#### https://gitmcp.io/docs

- Worked when I removed timeout handling in the HttpTransport ... !??
- When using this MCP server try the following prompt.

```
Can you find any code that refers to handling timeouts in an MCP client from the following repository? https://github.com/modelcontextprotocol/inspector
```

#### https://hf.co/mcp

- Doesn't work since it uses HTTP but not streaming
- Pending

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

### Interactivity

Consider `crystal-term/prompt`. I'd like a more interactive input prompt for the app.

- https://github.com/crystal-term/prompt

### Web interface

Consider [Kemal](https://github.com/kemalcr/kemal) to support a built-in web UI that mimics the CLI.

And use [BakedFileSystem](https://github.com/ralsina/baked_file_system) to bundle the static file in the binary.

And [Svelte](https://svelte.dev/docs/svelte/overview) with TypeScript (of course!) would be nice to write the web UI since it can be used to produce a SPA that can be "baked" into the binary.

