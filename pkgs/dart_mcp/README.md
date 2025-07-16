[![pub package](https://img.shields.io/pub/v/dart_mcp.svg)](https://pub.dev/packages/dart_mcp)
[![package publisher](https://img.shields.io/pub/publisher/dart_mcp.svg)](https://pub.dev/packages/dart_mcp/publisher)

A Dart package for making MCP servers and clients.

**Note**: This package is still experimental and is likely to evolve quickly.

## Implementing Servers

To implement a server, import `package:dart_mcp/server.dart` and extend the
`MCPServer` class. You must provide the server a communication channel to send
and receive messages with.

For each specific MCP capability or utility your server supports, there is a
corresponding mixin that you can use (`ToolsSupport`, `ResourcesSupport`, etc).

Each mixin has doc comments explaining how to use it - some may require you to
provide implementations of methods, while others may just expose new methods
that you can call.

See the [server example](example/simple_server.dart) for some example code.

### Invoking Client Capabilities

All client capabilities are exposed as methods on the `MCPServer` class.

Before attempting to call these methods, you must first wait for the
`MCPServer.initialized` future and then check the capabilities of the
client by reading the `MCPServer.clientCapabilities`.

Alternatively, if your server requires certain capabilities from the client for
all operations, you may override the `MCPServer.initialize` function and return
an error, which may result in a better UX for the users of the client.

## Implementing Clients

To implement a client, import `package:dart_mcp/client.dart` and extend the
`MCPClient` class, or directly call its constructor with a
`Implementation` if you aren't implementing any "capabilities".

For each specific MCP capability your client supports, there is a corresponding
mixin that you can use (`RootsSupport`, `SamplingSupport`, etc). Each mixin has
doc comments explaining how to use it - some may require you to provide
implementations of methods, while others may just expose new methods that you
can call.

### Connecting to Servers

You can connect this client with STDIO servers using the
`MCPClient.connectStdioServer` method, or you can call `MCPClient.connectServer`
with any other communication channel.

The returned `ServerConnection` should be used for all interactions with the
server, starting with a call to `ServerConnection.initialize`, followed up with
a call to `ServerConnection.notifyInitialized` (if initialization was
successful). If a version could not be negotiated or a server does not support
required features, the server connection should be closed (by calling
`ServerConnection.shutdown`).

See [initialization lifecycle][initialization_lifecycle] for information about
the client/server initialization protocol.

### Invoking Server Capabilities and Utilities

All server capabilities and utilities are exposed as methods or streams on the
`ServerConnection` class.

Before attempting to call methods on the server however, you should first verify
the capabilities of the server by reading them from the `InitializeResult` returned
from `ServerConnection.initialize`.

[initialization_lifecycle]: https://spec.modelcontextprotocol.io/specification/2024-11-05/basic/lifecycle/#initialization

## Supported Protocol Versions

[2024-11-05](https://spec.modelcontextprotocol.io/specification/2024-11-05/)
[2025-03-26](https://spec.modelcontextprotocol.io/specification/2025-03-26/)
[2025-06-18](https://spec.modelcontextprotocol.io/specification/2025-06-18/)

If support for a given protocol version is dropped, that will be released as a
breaking change in this package.

However, we will strive to maintain backwards compatibility where possible.

## Base Utilities

This table describes the state of implementation for the base protocol
[utilities](https://spec.modelcontextprotocol.io/specification/2024-11-05/basic/utilities).

Both the `MCPServer` and `MCPClient` support these.

| Utility | Support | Notes |
| --- | --- | --- |
| [Ping](https://spec.modelcontextprotocol.io/specification/2024-11-05/basic/utilities/ping) | :heavy_check_mark: |  |
| [Cancellation](https://spec.modelcontextprotocol.io/specification/2024-11-05/basic/utilities/cancellation/) | :x: | https://github.com/dart-lang/ai/issues/37 |
| [Progress](https://spec.modelcontextprotocol.io/specification/2024-11-05/basic/utilities/progress/) | :heavy_check_mark: |  |

## Transport Mechanisms

This table describes the supported
[transport mechanisms](https://modelcontextprotocol.io/specification/2025-03-26/basic/transports).

At its core this package is just built on streams, so any transport mechanism
can be used, but some are directly supported out of the box.

| Transport | Support | Notes |
| --- | --- | --- |
| [Stdio](https://modelcontextprotocol.io/specification/2025-03-26/basic/transports#stdio) | :heavy_check_mark: |  |
| [Streamable HTTP](https://modelcontextprotocol.io/specification/2025-03-26/basic/transports#streamable-http) | :x: | Unsupported at this time, may come in the future. |

## Batching Requests

Both the client and server support processing batch requests, but do not support
creating batch requests at this time.

## Authorization

Authorization is not supported at this time. This package is primarily targeted
at local MCP server usage for now.

## Server Capabilities

This table describes the state of implementation for the
[server capabilities](https://spec.modelcontextprotocol.io/specification/2024-11-05/server/).

**Note:** Servers can also invoke all [client capabilities](#client-capabilities),
see [Invoking Client Capabilities](#invoking-client-capabilities).

| Capability | Support | Notes |
| --- | --- | --- |
| [Prompts](https://spec.modelcontextprotocol.io/specification/2024-11-05/server/prompts/) | :heavy_check_mark: |  |
| [Resources](https://spec.modelcontextprotocol.io/specification/2024-11-05/server/resources/) | :heavy_check_mark: |  |
| [Tools](https://spec.modelcontextprotocol.io/specification/2024-11-05/server/tools/) | :heavy_check_mark: |  |

## Server Utilities

This table describes the state of implementation for the
[server utilities](https://spec.modelcontextprotocol.io/specification/2024-11-05/server/utilities/).

| Utility | Support | Notes |
| --- | --- | --- |
| [Completion](https://spec.modelcontextprotocol.io/specification/2024-11-05/server/utilities/completion/) | :heavy_check_mark: |  |
| [Logging](https://spec.modelcontextprotocol.io/specification/2024-11-05/server/utilities/logging/) | :heavy_check_mark: |  |
| [Pagination](https://spec.modelcontextprotocol.io/specification/2024-11-05/server/utilities/pagination/) | :construction: | https://github.com/dart-lang/ai/issues/28 |

## Client Capabilities

This table describes the state of implementation for the client
[capabilities](https://spec.modelcontextprotocol.io/specification/2024-11-05/client/).

**Note:** Clients can also invoke all [server capabilities](#server-capabilities)
and [server utilities](#server-utilities),
see [Invoking Server Capabilities and Utilities](#invoking-server-capabilities-and-utilities).

| Capability | Support | Notes |
| --- | --- | --- |
| [Roots](https://spec.modelcontextprotocol.io/specification/2024-11-05/client/roots/)| :heavy_check_mark: | |
| [Sampling](https://spec.modelcontextprotocol.io/specification/2024-11-05/client/sampling/)| :heavy_check_mark: | |
