# NOTES

## MCP Support

Currently we only support HTTP + Streaming via POST method. We do not support the deprecated SSE transport.

### Some MCP servers with tools

#### https://remote.mcpservers.org/fetch/mcp

- Works

#### https://echo.mcp.inevitable.fyi/mcp

- Works

#### https://time.mcp.inevitable.fyi/mcp

- Works
- Occasionally fails but I think this is a server problem

#### https://gitmcp.io/docs

- Worked when I removed timeout handling in the HttpTransport ... !??
- When using this MCP server try the following prompt.

```
Can you find any code that refers to handling timeouts in an MCP client from the following repository? https://github.com/modelcontextprotocol/inspector
```

#### https://hf.co/mcp

- Doesn't work since it uses HTTP but not streaming
- Pending