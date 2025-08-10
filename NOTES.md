# NOTES

## TODO

- [ ] Write test specs
- [ ] Document the code classes (viz. fix `ops lint` warnings)

### MCPC

- [ ] Figure out how to support authentication (a) oAuth2 per spec? (b) API key? (c) Basic auth over HTTPS?
- [ ] Detect when MCP connection needs to be reset; there are some rules for this.
- [ ] Find a canonical server to run locally to test the protocol better
- [ ] Figure out how to improve MCP transport responsiveness. The MCP Inspector seems be deal with HTTP streaming much more responsively. My implementation, which needs `io.skip_to_end` after handling every response, seems sluggish.

## MCP Support

Currently we only support HTTP + Streaming via POST method. Also support non-streaming HTTP but I haven't found a good server to test this. 
We do not support the deprecated SSE transport.

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

### Interactivity

Consider `crystal-term/prompt`. I'd like a more interactive input prompt for the app.

- https://github.com/crystal-term/prompt

### Web interface

Consider [Kemal](https://github.com/kemalcr/kemal) to support a built-in web UI that mimics the CLI.

And use [Rucksack](github.com/busyloop/rucksack) to bundle the static file in the binary.

