## 0.2.3-wip

- Added error checking to required fields of all `Request` subclasses so that
  they will throw helpful errors when accessed and not set.
- Added enum support to Schema.

## 0.2.2

- Refactor `ClientImplementation` and `ServerImplementation` to the shared
  `Implementation` type to match the spec. The old names are deprecated but will
  still work until the next breaking release.
- Add `clientInfo` field to `MCPServer`, assigned during initialization.
- Move the `done` future from the `ServerConnection` into `MCPBase` so it is
  available to the `MPCServer` class as well.

## 0.2.1

- Fix the `protocolLogSink` support when using `MCPClient.connectStdioServer`.
- Update workflow example to show thinking spinner and input and output token
  usage.
- Update file system example to support relative paths.
- Fix a bug in notification handling where leaving off the parameters caused a
  type exception.
- Added `--help`, `--log`, and `--model` flags to the workflow example.
- Fixed a bug where the examples would only connect to a server with the latest
  protocol version.
- Handle failed calls to `listRoots` in the `RootsTrackingSupport` mixin more
  gracefully. Previously this would leave the `roots` future hanging
  indefinitely, but now it will log an error and set the roots to empty.
- Added validation for Schema extension.
- Fixed an issue where getting the type of a Schema with a null type would
  throw.

## 0.2.0

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
- **Breaking**: Change the `InitializeResult`'s `instructions` to `String?` to
  reflect that not all servers return instructions.
- Change the `MCPServer.fromStreamChannel` constructor to make the `instructions`
  parameter optional.
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
