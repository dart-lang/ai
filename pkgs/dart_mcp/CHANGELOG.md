## 0.2.0-wip

- Support protocol version 2025-03-26.
  - Adds support for `AudioContent`.
  - Adds support for `ToolAnnotations`.
  - Adds support for `ProgressNotification` messages.
- Save the `ServerCapabilities` object on the `ServerConnection` class to make
  it easier to check the capabilities of the server.
- Add default version negotiation logic.
  - Save the negotiated `ProtocolVersion` in a `protocolVersion` field for both
    `MCPServer` and the `ServerConnection` classes.
  - Automatically disconnect from servers if version negotiation fails.
- Added support for adding and listing `ResourceTemplate`s.
  - Handlers have to handle their own matching of templates.
- Added a `RootsTrackingSupport` server mixin which can be used to keep an
  updated list of the roots set by the client.
- Added default throttling with a 500ms delay for
  `ResourceListChangedNotification`s and `ResourceUpdatedNotification`s. The
  delay can be modified by overriding
  `ResourcesSupport.resourceUpdateThrottleDelay`.
- Add `Sink<String> protocolLogSink` parameters to server constructor and client
  connection methods, which can be used to capture protocol messages for
  debugging purposes.
- Only send notifications if the peer is still connected. Fixes issues where
  notifications are delayed due to throttling and the client has since closed.
- **Breaking**: Fixed paginated result subtypes to use `nextCursor` instead of
  `cursor` as the key for the next cursor.
- **Breaking**: Change the `ProgressNotification.progress` and
  `ProgressNotification.total` types to `num` instead of `int` to align with the
  spec.
- **Breaking**: Change the `protocolVersion` string to a `ProtocolVersion` enum,
  which has all supported versions and whether or not they are supported.
- **Breaking**: Change `InitializeRequest` and `InitializeResult` to take a
  `ProtocolVersion` instead of a string.
- **Breaking**: Change the `InitializeResult`'s `instructions` to `String?` to reflect
  that not all servers return instructions.
- **Breaking**: Change `MCPBase` to accept a `StreamChannel<String>` instead of
  a `Peer`, and construct its own `Peer`.
- **Breaking**: Add `protocolLogSink` optional parameter to connect methods on
  `MCPClient`.
- **Breaking**: Move `channel` parameter on `MCPServer.new` to a positional
  parameter for consistency.

## 0.1.0

- Initial release, supports all major MCP functionality for both clients and
  servers, at protocol version 2024-11-05.
- APIs may change frequently until the 1.0.0 release based on feedback and
  needs.
