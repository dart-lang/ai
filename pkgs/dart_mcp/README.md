Dart SDK for implementing MCP servers and clients.

## Implementing Servers

To implement a server, import `package:dart_mcp/server.dart` and extend the
`MCPServer` class. You must provide the server a communication channel to send
and receive messages with.

For each specific MCP capability or utility your server supports, there is a
corresponding mixin that you can use (`ToolsSupport`, `ResourcesSupport`, etc).

Each mixin has doc comments explaining how to use it - some may require you to
provide implementations of methods, while others may just expose new methods
that you can call.

Before attempting to call methods on the client, you should first wait for the
`initialized` future and then check the capabilities of the client by reading
the `clientCapabilities`.

See the [server example](example/server.dart) for some example code.

## Implementing Clients

To implement a client, import `package:dart_mcp/client.dart` and extend the
`MCPClient` class.

### Connecting to Servers

You can connect this client with STDIO servers using the `connectStdioServer`
method, or you can call `connectServer` with any other communication channel.

The returned `ServerConnection` should be used for all interactions with the
server, starting with a call to `initialize`, followed up with a call to
`notifyInitialized` (if initialization was successful). If a version could not
be negotiated, the server connection should be shut down (by calling
`shutdown`).

For each specific MCP capability your client supports, there is a corresponding
mixin that you can use (`RootsSupport`, `SamplingSupport`, etc).

Each mixin has doc comments explaining how to use it - some may require you to
provide implementations of methods, while others may just expose new methods
that you can call.

Before attempting to call methods on the server, you should first verify the
capabilities of the server by reading them from the `InitializeResult`.

See the [client example](example/client.dart) for some example code.

## Supported Protocol Versions

[2024-11-05](https://spec.modelcontextprotocol.io/specification/2024-11-05/)

## Server Capabilities

| Capability | Support | Notes |
| --- | --- | --- |
| [Prompts](https://spec.modelcontextprotocol.io/specification/2024-11-05/server/prompts/) | :heavy_check_mark: |  |
| [Resources](https://spec.modelcontextprotocol.io/specification/2024-11-05/server/resources/) | :heavy_check_mark: |  |
| [Tools](https://spec.modelcontextprotocol.io/specification/2024-11-05/server/tools/) | :heavy_check_mark: |  |

## Server Utilities

| Utility | Support | Notes |
| --- | --- | --- |
| [Completion](https://spec.modelcontextprotocol.io/specification/2024-11-05/server/utilities/completion/) | :heavy_check_mark: |  |
| [Logging](https://spec.modelcontextprotocol.io/specification/2024-11-05/server/utilities/logging/) | :heavy_check_mark: |  |
| [Pagination](https://spec.modelcontextprotocol.io/specification/2024-11-05/server/utilities/pagination/) | :construction: | https://github.com/dart-lang/ai/issues/28 |

## Client Capabilities

| Capability | Support | Notes |
| --- | --- | --- |
| [Roots](https://spec.modelcontextprotocol.io/specification/2024-11-05/client/roots/)| :heavy_check_mark: | |
| [Sampling](https://spec.modelcontextprotocol.io/specification/2024-11-05/client/sampling/)| :heavy_check_mark: | |
