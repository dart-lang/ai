## 0.3.3-wip

- Fix `PingRequest` handling when it is sent from a non-Dart client.
- Deprecate `ElicitationAction.reject` and replace it with
  `ElicitationAction.decline`.
  - In the initial elicitations schema this was incorrectly listed as `reject`.
  - This package still allows `reject` and treats it as an alias for`decline`.
  - The old `reject` enum value was replaced with a static constant equal
    exactly to `decline`, so switches are not affected.
- Add `title` parameter to `Prompt` constructor.

## 0.3.2

- Deprecate the `EnumSchema` type in favor of the `StringSchema` with an
  `enumValues` parameter. The `EnumSchema` type was not MCP spec compatible.
  - Also deprecated the associated JsonType.enumeration which doesn't exist
    in the JSON schema spec.

## 0.3.1

- Fixes communication problem when a `MCPServer` is instantiated without
  instructions.
- Fix the `content` argument to `PromptMessage` to be a single `Content` object.
- Add new `package:dart_mcp/stdio.dart` library with a `stdioChannel` utility
  for creating a stream channel that separates messages by newlines.
- Added more examples.
- Deprecated the `WithElicitationHandler` interface - the method this required
  is now defined directly on the `ElicitationSupport` mixin which matches the
  pattern used by other mixins in this package.
- Change the `schema` parameter for elicitation requests to an `ObjectSchema` to
  match the spec.
- Deprecate the `Elicitations` server capability, this doesn't exist in the spec.

## 0.3.0

- Added error checking to required fields of all `Request` subclasses so that
  they will throw helpful errors when accessed and not set.
- Added enum support to Schema.
- Add more detail to type validation errors.
- Remove some duplicate validation errors, errors are only reported for the
  leaf nodes and not all the way up the tree.
  - Deprecated a few validation error types as a part of this, including
    `propertyNamesInvalid`, `propertyValueInvalid`, `itemInvalid` and
    `prefixItemInvalid`.
- Added a `custom` validation error type.
- **Breaking**: Auto-validate schemas for all tools by default. This can be
  disabled by passing `validateArguments: false` to `registerTool`.
- Updates to the latest MCP spec, [2025-06-08](https://modelcontextprotocol.io/specification/2025-06-18/changelog)
  - Adds support for Elicitations to allow the server to ask the user questions.
  - Adds `ResourceLink` as a tool return content type.
  - Adds support for structured tool output.
- **Breaking**: Change `MCPClient.connectStdioServer` signature to accept stdin
  and stdout streams instead of starting processes itself. This enables custom
  process spawning (such as using package:process), and also enables the client
  to run in browser environments.
- Fixed a problem where specifying `--log-file` would cause the server to stop
  working.

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
