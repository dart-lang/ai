## 0.6.0-wip

- Add a local HTTP probe for the MCP conformance suite.
- **BREAKING**:
  - `MCPBase` (including the `MCPServer.fromStreamChannel` and
    `ServerConnection.fromStreamChannel` constructors),
    `MCPClient.connectServer`, `MCPServerFactory`, and `stdioChannel` now
    operate on `StreamChannel<Map<String, Object?>>` instead of
    `StreamChannel<String>`, so JSON is encoded and decoded only at the
    transport edge rather than once more within the process.
    - `stdioChannel` still speaks newline-delimited JSON on the wire, and now
      itself answers frames which are not JSON objects with JSON-RPC error
      responses. To migrate other message-framed `StreamChannel<String>`
      transports, wrap them in the new `jsonRpcChannel` helper in
      `package:dart_mcp/stdio.dart`, which adapts them the same way.
    - JSON-RPC batch frames are no longer accepted. Batching was added in
      protocol version 2025-03-26 and removed in 2025-06-18; a batch now gets
      a single invalid request error response.
    - Frames rejected at the transport edge, and the error responses they
      produce, do not appear in `protocolLogSink`, which now logs each
      message re-encoded as JSON, falling back to `toString` for messages
      which cannot be encoded.
    - On in-memory channels, `RpcException.data` is no longer normalized by a
      JSON round trip, so it can be an untyped map.
  - Separate server feature registration from the legacy protocol handshake.
    `MCPServer.initialize` now accepts an `MCPServerInitialization` containing
    the protocol version, client information, and client capabilities, and
    returns nothing. The client information is optional, since clients are no
    longer required to send it on every request, see
    https://github.com/modelcontextprotocol/modelcontextprotocol/pull/3002.
    `MCPServer.clientInfo` is now nullable (`Implementation?`).
  - Mixins and subclasses declare what a server supports by editing the
    `MCPServer.capabilities` field, which is `final`, instead of editing the
    `ServerCapabilities` on the `InitializeResult` that `super.initialize`
    used to return.
    - A mixin that returned a fresh object kept the handlers the rest of the
      chain had registered while dropping the capabilities they declared, so
      the server answered requests it did not advertise.
    - The initialize response that `MCPServer.initializeLegacy` returns takes
      its capabilities from that field.
    - On the client, `MCPClient.capabilities` already worked this way.
  - Override `MCPServer.initializeLegacy` only to customize the legacy
    initialize response or version negotiation.
  - On revisions that have `elicitation/create`,
    `ElicitationRequestSupport.elicit` now throws an `RpcException` with
    `McpErrorCodes.missingRequiredClientCapability` instead of a `StateError`
    when the client did not declare the capability the request needs, naming
    the missing capability under `data.requiredCapabilities`, which the
    2026-07-28 revision requires of that error.
    `ToolsSupport.callTool` rethrows an `RpcException`, so a tool which elicits
    reaches the client as that error rather than as a `CallToolResult` whose
    text is a Dart stack trace. A server catching the `StateError` needs to
    catch `RpcException` instead, which comes from `package:json_rpc_2`.
  - `ElicitationRequestSupport.elicit` also checks which mode a request names
    on those same revisions. A server that guarded on `supportsElicitation`
    should read `supportsFormElicitation` or `supportsUrlElicitation`. A
    request naming an unknown mode is answered with `-32602` (invalid params)
    instead of going out with that mode still on it.
  - `ServerConnection` now answers an elicitation mode the client did not
    declare with `-32602` (invalid params), where it used to answer a `decline`,
    as if the user had sent it. An unrecognized one used to throw out of the
    handler instead. The `-32042` retry path leaves the error
    alone unless the request it carries names url.
  - `ResourcesSupport.readResource` now answers a URI it has no resource or
    template for with the `-32602` (invalid params) error the 2026-07-28
    revision requires, carrying the URI as `data.uri`, instead of letting an
    `ArgumentError` reach the client as a generic `-32000` server error with a
    Dart stack trace attached. A server which overrides `readResource` and
    catches the `ArgumentError` its dartdoc used to promise needs to catch
    `RpcException` from `package:json_rpc_2` instead.
  - On revisions before 2026-07-28, `MCPServer.listRoots` and
    `MCPServer.createMessage` now throw an `RpcException` with
    `McpErrorCodes.missingRequiredClientCapability` when the client did not
    declare `roots` or `sampling`, naming the missing capability under
    `data.requiredCapabilities`, the same way `ElicitationRequestSupport.elicit`
    already did. Both used to send the request anyway, so what came back
    depended on the peer: a client with no handler answered `-32601`, and a
    request-scoped transport answered `-32603` because it cannot carry a
    server to client request at all. A server which expects either of those
    codes for an undeclared capability should read `MCPServer.supportsRoots`
    or `MCPServer.supportsSampling` first.
  - `MCPServer.listRoots`, `MCPServer.createMessage`, and
    `ElicitationRequestSupport.elicit` now throw an `RpcException` with
    `-32603` when the negotiated protocol version does not have the method,
    before they read any client capability.
    `ProtocolVersion.v2026_07_28.removedMethods` now lists `roots/list`,
    `sampling/createMessage`, and `elicitation/create`, which that revision
    dropped along with the rest of the `ServerRequest` union, so
    `ProtocolVersion.methodIsValid` answers for all three. A server on it asks
    the client for input with an `InputRequiredResult` on `tools/call`,
    `prompts/get`, or `resources/read` instead, see
    https://modelcontextprotocol.io/specification/2026-07-28/basic/patterns/mrtr.
    `elicit` also throws on 2024-11-05 and 2025-03-26, the two revisions before
    2025-06-18 added `elicitation/create`.
  - `ResourceLink.icons` is now `List<Icon>?` instead of `List<String>?`, and
    its factory takes the icons, the way the other five types carrying `icons`
    already do. The field has been an array of icons since 2025-11-25 added it,
    see
    https://modelcontextprotocol.io/specification/2025-11-25/schema#resourcelink-icons.
    Reading it off a resource link a server sent threw a type error on the
    first element.
  - `LoggingSupport.loggingLevel` is now nullable (`LoggingLevel?`), `null`
    meaning `log` sends nothing. On 2026-07-28 `initialize` assigns the level
    the request named, over whatever the server set before it ran. Earlier
    revisions fill it in only when the server set none. `LoggingSupport` also
    stops registering `logging/setLevel` on that revision, which is what a
    transport dispatching on its own gets.
  - `IntegerSchema`'s four bounds and its default read `num` now, and its
    factory takes them that way. JSON Schema types the bounds `number`, and
    the spec gives integers and numbers one definition whose `minimum`,
    `maximum` and `default` are `number` too. A peer sending
    `{"type": "integer", "minimum": 0.5}` sent something the getter threw on.
    `multipleOf` next to them already read `num`.
  - `ServerConnection.protocolVersion` is nullable, and is `null` until
    something settles a version. It used to be a `late` field, which threw
    when read before then. Set `serverInfo` alongside it. Sampling hands that
    to the handler.
  - `ServerConnection.serverInfo` stays `null` when version negotiation fails,
    the way its dartdoc already described, instead of holding the rejected
    server's implementation. `initialize` still returns that result and
    `serverCapabilities` still holds what the server sent.
- Add `supportsFormElicitation` and `supportsUrlElicitation` for a server to
  ask before it sends. An empty `elicitation` object still means form, the way
  `elicitation` read before the split.
- Add `ElicitRequest.rawMode`, which carries the mode as it arrived. `mode`
  resolves it and throws on an unknown one.
- Fix the `Meta` dartdoc, which still described the 2025-06-18 prefix rule, and
  document the `traceparent`, `tracestate`, and `baggage` keys reserved for
  OpenTelemetry trace context, see
  https://modelcontextprotocol.io/specification/2026-07-28/basic#_meta.
- Add `handleRequestScopedMessage` and `MCPServerFactory`, which serve each
  decoded JSON-RPC message on a fresh server instance for request-scoped
  transports. On 2026-07-28, successful results record the server
  implementation under the reserved `io.modelcontextprotocol/serverInfo`
  result metadata key, carry a `resultType`, and on the list and read results
  carry the `ttlMs` and `cacheScope` hints, which the handler may set itself.
  A server answering an earlier revision gets none of them. Does **not** add
  any transport.
- On protocol 2026-07-28, `handleRequestScopedMessage` now validates
  input-required results before forwarding them, see
  https://modelcontextprotocol.io/specification/2026-07-28/basic/patterns/mrtr.
  Asking for a client capability that was never declared answers
  `McpErrorCodes.missingRequiredClientCapability`, a malformed shape an
  internal error.
- Support a per-request log level on 2026-07-28, see
  https://modelcontextprotocol.io/specification/2026-07-28/server/utilities/logging.
  The level goes in the `io.modelcontextprotocol/logLevel` metadata key, which
  `MCPServerInitialization` now carries and the Streamable HTTP handler reads
  off the envelope, answering invalid params when it is not a logging level.
- `Resource.size` reads `null` for an absent size instead of throwing a type
  error. The field is optional, and the getter cast it to a non-nullable `int`.
- `RootsTrackingSupport` no longer surfaces an unhandled error when the
  connection closes while a `listRoots` request is in flight.
- The URL elicitation retry rethrows the original error when its data is not
  a map, instead of failing with a type error.
- Add `Result.resultType`, modeling the `resultType` field, which the
  2026-07-28 draft schema types as an open union, see
  https://github.com/modelcontextprotocol/modelcontextprotocol/pull/2773.
  The getter returns a `String`, defaulting to `complete` when the field is
  absent, as the schema requires for backward compatibility with servers on
  earlier protocol versions.
- Add `CacheableResult` and the `CacheScope` enum, modeling the `ttlMs` and
  `cacheScope` caching hints which the 2026-07-28 draft schema attaches to
  several result types, see
  https://github.com/modelcontextprotocol/modelcontextprotocol/pull/2549.
  `ttlMs` returns an `int`, reading `0` (immediately stale) for an absent or
  negative value, as the spec instructs clients; `cacheScope` returns a
  `CacheScope?` which is `null` when the field is absent, rather than the
  "public" default the schema comment mentions, because the same SEP calls the
  field required "because there is no safe default for older servers" and
  leaves a default to each SDK. `ListToolsResult`, `ListPromptsResult`,
  `ListResourcesResult`, `ListResourceTemplatesResult`, and
  `ReadResourceResult` now implement `CacheableResult`, so the hints are
  readable on responses from servers that send them, and their factories take
  an optional `ttlMs` and `cacheScope`, which are left out when not passed.
- Add `McpErrorCodes.headerMismatch` (`-32020`),
  `.missingRequiredClientCapability` (`-32021`), and
  `.unsupportedProtocolVersion` (`-32022`), the error codes the 2026-07-28
  revision allocates from the `-32020` to `-32099` range it reserves for the
  specification, see
  https://modelcontextprotocol.io/specification/2026-07-28/basic#error-codes.
  The Streamable HTTP handler below now emits `McpErrorCodes.headerMismatch`
  and `.unsupportedProtocolVersion`. The same registry reserves `-32042`, so
  `urlElicitationRequired` now documents that only the 2025-11-25 revision
  emits it.
- Add `InputRequiredResult` and `InputRequest`, the result a server answers with
  when it needs input first, see
  https://modelcontextprotocol.io/specification/2026-07-28/basic/patterns/mrtr.
  A server built with this package does not send one yet.
- On a 2026-07-28 connection, `ServerConnection.callTool`, `.getPrompt` and
  `.readResource` answer an `input_required` result from the client's
  elicitation, sampling and roots handlers, then send the original request
  again, through the new `ServerConnection.sendRequestWithInputs`. The spec
  bounds the rounds nowhere, so `ServerConnection.maxInputRequiredRounds`
  stops them, at ten unless a caller moves it or clears it with `null`.
- Add `MCPBase.sendRequestKeepingProgress` and `MCPBase.closeProgress`.
  `sendRequest` closes a progress stream once its request is done, and this
  pair splits that apart so a retry loop can hold one token across rounds.
- Add `WithInputResponses`, the type a client's retry carries.
  `CallToolRequest`, `GetPromptRequest` and `ReadResourceRequest` take an
  `inputResponses` and a `requestState`, matching the three requests the schema
  answers with an `InputRequiredResult`.
- Add `SubscriptionFilter`, `SubscriptionsListenRequest`,
  `SubscriptionsListenResult`, and `SubscriptionsAcknowledgedNotification`,
  modeling the `subscriptions/listen` request the 2026-07-28 revision adds, see
  https://modelcontextprotocol.io/specification/2026-07-28/basic/patterns/subscriptions.
  `subscriptions/listen` opens one long-lived stream for the notifications
  which do not belong to a specific request, and it replaces three things: the
  HTTP GET endpoint, `resources/subscribe`, and `resources/unsubscribe`.
  `SubscriptionFilter.resourceSubscriptions` carries the resource URIs the last
  two took. `SubscribeRequest` and `UnsubscribeRequest` stay for the revisions
  which have them. Serving the request, and delivering notifications on the
  stream it opens, land as separate changes.
- Deprecate `IncludeContext.thisService` and replace it with `thisServer`, the
  name the specification uses, see
  https://modelcontextprotocol.io/specification/2026-07-28/client/sampling.
  Since the enum name is what a request carries, a server asking for that
  context sent a value only another dart_mcp client could match. The
  `CreateMessageRequest.includeContext` getter still reads `thisService`, since
  this package sent it up to 0.5.2. Reading the corrected name needs 0.6.0.
- Every getter returning a `double` now reads the JSON value as a `num` first.
  A peer sending `1` for `1.0` used to throw except on the JavaScript
  platforms. `CreateMessageRequest` takes `temperature` as a `num` because an
  `int` cannot express a fractional one.
- `NumberSchema`, `IntegerSchema` and `BooleanSchema` take a `default`, which
  the schema gives them and `StringSchema` already had. A server could
  pre-fill a text field on an elicitation form but not a number or a checkbox.
- Fix `uniqueItems` on a list schema, which compared items with `Set`, so two
  equal maps or lists decoded from JSON counted as different and a list the
  schema forbids validated. JSON Schema compares by structural equality.
- Stop `BaseMetadata`, `MetaWithProgressToken`, `CompletionContext`,
  `PromptReference` and `ElicitResult` from writing an explicit `null` for an
  optional field that was not given. The schema types all five as non-nullable.
- Fix `RequestId` so it can hold a JSON-RPC id. Its representation type was
  `json_rpc_2`'s `Parameter` rather than `Object`, which its sibling
  `ProgressToken` uses, so `CancelledNotification.requestId` threw for every
  id a peer can send and no id could be constructed to pass to the
  `CancelledNotification` factory.
- Add `ProtocolVersion.v2026_07_28`. `ProtocolVersion.latestSupported` still
  points at 2025-11-25, the newest version the legacy `initialize` handshake
  negotiates; transports for the request-scoped protocol carry their own set
  of supported versions.
- Add `DiscoverRequest` and `DiscoverResult`, modeling the `server/discover`
  request that the 2026-07-28 revision requires servers to implement, see
  https://modelcontextprotocol.io/specification/2026-07-28/server/discover.
  `DiscoverResult` implements `CacheableResult`, and reads
  `supportedVersions` as a `List<String>` rather than a
  `List<ProtocolVersion>`, because a server may list a version this package
  has no name for and the client is the one choosing between them. Its factory
  takes `ttlMs` and `cacheScope` on the same terms as the other five cacheable
  results, so the sixth operation the caching rules name is no longer the one
  that cannot carry the hints.
- Answer a request whose handler emits related notifications on an SSE
  response stream. A quiet handler keeps its JSON body. List changes and
  resource updates reach `onNotification` alone, since this revision carries
  those on a `subscriptions/listen` stream. Does not treat a closed stream as
  cancellation, which the specification requires.
- Add `sseMessageStream`, decoding the `message` events of an SSE response
  into JSON objects. Undecodable data becomes an error event without ending
  the stream, though `await for` stops on the first one.
- Serve `server/discover` from `MCPServer.discover`, which answers with the
  request-scoped protocol versions this package implements, the capabilities
  `MCPServer.initialize` registered, and the instructions the server was given.
  - Its result joins the ones carrying `ttlMs` and `cacheScope`, and the
    dispatcher stamps the result type and the server's identity on it as it
    does for every result.
  - Only a server initialized for 2026-07-28 or later registers the handler,
    since answering is how a server declares it speaks the request-scoped
    protocol.
  - A server on an earlier revision that answered would be taken for a modern
    one, see
    https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/stdio#backward-compatibility.
  - The advertisement removes `subscribe` and the three `listChanged` bits,
    since a client only hears those notifications over a
    `subscriptions/listen` stream, and this package does not serve that
    request yet.
  - Every other key on those capabilities goes out as it is, and so does the
    rest of the field, since capabilities are an open set.
    `initializeLegacy` still sends all of them.
  - The `ServerCapabilities` constructor writes `completions`, which it used to
    drop, so a caller that passes one gets it back.
- Add `package:dart_mcp/streamable_http.dart` with
  `handleStreamableHttpRequest`, the server side of the Streamable HTTP
  transport from the 2026-07-28 revision, see
  https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http.
  Each POST carries one JSON-RPC request or notification which is validated
  against the required headers and `_meta` envelope, then dispatched to a
  fresh server instance via `handleRequestScopedMessage`. See
  `example/streamable_http_server.dart`. Does not add the legacy session
  routes or an HTTP client; those land as separate changes.
- Add `ProtocolVersion.addedMethods` and `.removedMethods`, listing what each
  revision of the protocol introduced and took out, and
  `ProtocolVersion.methodIsValid`, which walks back from a revision to answer
  whether it has a method.
- Reject the methods the 2026-07-28 revision removed with `404` and
  `-32601` in `handleStreamableHttpRequest`. Until now
  `ping` answered `200` on every server, and `logging/setLevel`,
  `resources/subscribe`, and `resources/unsubscribe` reached their handlers on
  a server which mixes in `LoggingSupport` or `ResourcesSupport`. A request for
  `notifications/roots/list_changed` reached one where the client asked for
  roots. Notifications are still acknowledged with `202` before this check.
- Add instructions to read the schema when tool arguments fail validation.
- Add `ClientCapabilities.extensions` and `ServerCapabilities.extensions`, the
  extension-support maps the 2026-07-28 revision adds to both capability
  objects alongside the `experimental` maps, see
  https://modelcontextprotocol.io/extensions/overview for the identifier
  format. The client map is carried by the legacy `initialize` request and by
  the `io.modelcontextprotocol/clientCapabilities` envelope key the
  Streamable HTTP handler already requires; the server map travels with
  `ServerCapabilities`, which is held by the legacy `initialize` result and
  by `DiscoverResult`.
- Support `x-mcp-header` in `handleStreamableHttpRequest`. A `tools/call`
  argument annotated with it is checked against its `Mcp-Param-{Name}` header.
  - Nested `properties` paths and `=?base64?...?=` values are supported, and
    integers are compared numerically.
  - A missing, extra, malformed, or mismatched header answers `400 Bad Request`
    with `McpErrorCodes.headerMismatch` and drops any notification the server
    emitted before dispatch.
  - A `tools/call` whose `arguments` is not an object answers `400 Bad Request`
    with invalid params.
  - `handleRequestScopedMessage` gained `beforeDispatch`, and
    `ToolsSupport.registeredTools` exposes the registered tools by name.
- Point the documentation at `modelcontextprotocol.io` and at protocol
  revision 2025-11-25. The old host stopped serving HTTPS, and the old
  revision number 2025-11-05 was never a published revision.
- Add missing license headers.
- Add `MetaWithRequestEnvelope`, a `_meta` type for the reserved keys a request
  on the 2026-07-28 revision carries.
- Add `ServerConnection.discover`, the client side of `server/discover`.
  - The request carries `protocolVersion` and `capabilities` under the two
    reserved keys the schema makes required, plus `clientInfo`, `logLevel` and
    `progressToken` when they are given, see
    https://modelcontextprotocol.io/specification/2026-07-28/server/discover.

## 0.5.2

- Update `listRoots` to normalize URIs to file: scheme variants when given raw
  file paths. This fixes non-spec compliant clients.

## 0.5.1

- Always send a properties object for tool input schemas, see
  https://github.com/dart-lang/ai/issues/170.

## 0.5.0

- Initial support for protocol version [2025-11-25](https://modelcontextprotocol.io/specification/2025-11-25/).
  - Added support for `Icon`s in `Implementation`, `Tool`, `Resource`, `ResourceTemplate`, and `Prompt`.
  - Added support for `ToolChoice` in sampling `CreateMessageRequest`.
  - Added support for URL-based elicitations in `ElicitRequest`.
    - Separated `ElicitationSupport` into `ElicitationFormSupport` and
      `ElicitationUrlSupport` mixins, which will affect which capabilities
      your server advertises. The original `ElicitationSupport` mixin is now
      deprecated (and is an alias for `ElicitationFormSupport`).
    - Added `onElicitationComplete` extension getter to `ElicitRequest`, which
      will listen for `notifications/elicitation/complete` notifications.
    - If a tool call fails with the `urlElicitationRequired` error code, and
      the client supports URL based elicitations, the client will automatically
      handle the elicitation and retry the tool call if the elicitation
      succeeds.
  - Added an `McpErrorCodes` namespace for MCP error codes. For now only
    contains the `urlElicitationRequired` error code.
  - Added examples for URL based elicitations, including handling
    `urlElicitationRequired` errors.
  - Added `description` field to `Implementation`.
  - Does **not** add support for Tasks yet.
  - Added support for `EnumSchema` subtypes, matching the spec. This includes
    multi select enums and enums with titles. Validation is also supported.
  - Added `Meta? meta` param to `ElicitRequest`.
- Added `ConstSchema` type for constant values, with validation.
- **BREAKING**:
  - Change many fields of `ResourceLink` to be nullable, and their associated
    parameters to be optional. This brings us in line with the specification.
  - The `WithElicitationHandler` interface is now private and implemented by
    the `ElicitationFormSupport` and `ElicitationUrlSupport` mixins.
  - Added a required `ServerConnection server` parameter to the
    `ElicitationSupport.handleElicitation` method.
  - `ElicitRequest.requestedSchema` is now nullable (for url mode).
  - `EnumSchema` is now a union type with 4 subtypes, matching the spec changes.

## 0.4.1

- Expose various private methods on MCP server mixins as public methods, with
  `@mustCallSuper` annotations. This allows intercepting calls for logging,
  metrics, or other purposes.
- Fix the `resource` parameter type on `EmbeddedResource` to be
  `ResourceContents` instead of `Contents`.
  - **Note**: This is technically breaking but the previous API would not have
    been possible to use in a functional manner, so it is assumed that it had
    no usage previously.
- Fix the `type` getter on `EmbeddedResource` to read the actual type field.
- Add `toJson` method to the `CreateMessageResult` of a sampling request.

## 0.4.0

- Update the tool calling example to include progress notifications.
- **Breaking**: Update APIs to accept nullable parameters when the parameters
  are not required for that method. This is only breaking if you override these
  methods.

## 0.3.3

- Fix `PingRequest` handling when it is sent from a non-Dart client.
- Deprecate `ElicitationAction.reject` and replace it with
  `ElicitationAction.decline`.
  - In the initial elicitations schema this was incorrectly listed as `reject`.
  - This package still allows `reject` and treats it as an alias for`decline`.
  - The old `reject` enum value was replaced with a static constant equal
    exactly to `decline`, so switches are not affected.
- Add `title` parameter to `Prompt` constructor.
- Only execute sub-processes in a shell if they are `.bat` files.

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
