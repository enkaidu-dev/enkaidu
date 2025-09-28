# JSON RPC 

The `JsonRpc` module provides the definition for base JSON RPC object types:

- `Request(P)` that can be subclassed to defined JSON-serializable JSON RPC requests, where `P` defines the type for the `params` property. 
- `Notification(P)` that can be subclassed to defined JSON-serializable JSON RPC notifications, where `P` defines the type for the `params` property. 
- `Response(R)` that can be subclassed to defined JSON-serializable JSON RPC responses, where `R` defines the type for the `result` property. 

> These notions may be specific to the ways in which the MCP and ACP protocols use JSON RPC.
