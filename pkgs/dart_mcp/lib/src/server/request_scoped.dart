// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'server.dart';

/// Creates the [MCPServer] which communicates over [channel].
///
/// The returned server must be constructed on [channel], typically by passing
/// it to [MCPServer.fromStreamChannel].
typedef MCPServerFactory =
    MCPServer Function(StreamChannel<Map<String, Object?>> channel);

/// Handles one decoded JSON-RPC [message] on a fresh server instance.
///
/// In a request-scoped lifecycle there is no connection to initialize: every
/// request carries its own client context, see
/// https://modelcontextprotocol.io/specification/draft/basic. This function
/// creates a server with [serverFactory], runs [MCPServer.initialize] with
/// the [initialization] built by the transport, completes
/// [MCPServer.initialized], and then delivers [message] to the server as if
/// it had arrived over a connection. The server handles this one message and
/// is shut down afterward; it is never reused, and no state carries over
/// between messages. Decoding the wire format, extracting the per-request
/// context, and anything HTTP-specific stay in the transport. Protocol
/// metadata carried in [message]'s own `_meta` is not read here;
/// a successful `subscriptions/listen` result keeps the exchange open until
/// the server shuts down.
/// [initialization] is the sole source of the per-request context.
///
/// [message] is a request if it has a non-null `id` member and a notification
/// otherwise. Returns the decoded JSON-RPC response for a request, and `null`
/// for a notification, which per JSON-RPC gets no response. A successful
/// result records the server's [MCPServer.implementation] under the reserved
/// `io.modelcontextprotocol/serverInfo` result metadata key, carries a
/// `resultType`, and, for the requests the caching rules name, carries `ttlMs`
/// and `cacheScope` unless it is an interim `resources/read` result, which is
/// not cacheable. The acknowledgement and result for `subscriptions/listen`
/// carry the request id under `io.modelcontextprotocol/subscriptionId`.
/// A listen request is named before delivery by setting
/// [SubscriptionsSupport.nextSubscriptionId] to that id. A
/// field the handler left out is filled in: a `resultType`
/// left `null` becomes `complete`, a `ttlMs` which is `null` becomes `0`, and
/// a `cacheScope` which is `null` becomes `private`. The dispatcher cannot
/// know when an answer goes stale, and `public` is the one guess which could
/// put a private answer in a cache shared across authorization contexts.
/// A `ttlMs` below zero or a `cacheScope` outside `public` and `private` is a
/// bug in the server: it asserts, and in a build with asserts disabled it is
/// replaced the same way a field left `null` is. None of this reaches a result
/// on an earlier revision, and every error response is returned unchanged. On
/// 2026-07-28 an `input_required` result the client cannot act on is refused
/// here, not sent on: one on a method the revision does not answer that way
/// asserts and returns an internal error, and one asking for a
/// capability the client left out is
/// [McpErrorCodes.missingRequiredClientCapability]. If the server closes
/// before responding to a request, an internal-error response is returned
/// instead. The server may still be processing a notification when the
/// returned future completes.
///
/// The returned future completes once the server responds or the exchange
/// closes; it does not time out on its own. A handler that never returns
/// leaves it pending and the server alive. To bound execution, retain the
/// server your factory creates and call [MCPServer.shutdown] on it; the
/// exchange then completes with an internal-error response.
/// A successful `subscriptions/listen` result is returned after that shutdown.
///
/// The [MCPServer.capabilities] a server registers are intentionally not
/// surfaced here: in this lifecycle clients discover capabilities with
/// `server/discover`, which [MCPServer.discover] answers, rather than per
/// message.
///
/// Notifications the server emits during the exchange, including any it emits
/// while initializing, are passed to [onNotification] with their JSON-RPC
/// envelope so a transport can decide how to deliver them. Errors thrown by
/// [onNotification] are reported as uncaught errors and do not fail the
/// exchange.
///
/// Requests from the server back to the client, such as `roots/list`, cannot
/// be answered within a single-message exchange: they fail with an
/// [RpcException] inside their handler, or with a [StateError] if the exchange
/// has already been torn down. When the negotiated revision does not have one,
/// [MCPServer.listRoots], [MCPServer.createMessage], and
/// [ElicitationRequestSupport.elicit] refuse it before it gets this far.
/// 2026-07-28 has none of the three. It dropped `ping` as well, and
/// [MCPBase.ping] does not read the revision, so a ping still fails inside its
/// handler.
///
/// If [beforeDispatch] is given, it receives the initialized server and runs
/// before [message] is delivered. A non-`null` result stops dispatch: requests
/// receive the serialized error and notifications receive no response.
///
/// Throws an [ArgumentError] if [message] is not a JSON-RPC request or
/// notification (no string `method`, a `null` id, or a `result` or `error`
/// member), or if its method is the legacy `initialize` request or
/// `initialized` notification; classifying a message as legacy or
/// request-scoped is the transport's job. Errors thrown by [serverFactory] or
/// by [MCPServer.initialize] propagate to the caller; a server that was
/// created is shut down first.
// TODO: Route server-to-client requests on revisions before 2026-07-28.
// https://github.com/dart-lang/ai/issues/162
Future<Map<String, Object?>?> handleRequestScopedMessage(
  Map<String, Object?> message,
  MCPServerInitialization initialization,
  MCPServerFactory serverFactory, {
  void Function(Map<String, Object?> notification)? onNotification,
  FutureOr<RpcException?> Function(MCPServer server)? beforeDispatch,
}) async {
  final object = JsonRpc2Object.fromMap(message);
  if (object.kind == JsonRpc2Kind.response) {
    throw ArgumentError.value(
      message,
      'message',
      'A request or notification must not carry a result or error',
    );
  }
  final method = object.method;
  if (method == null) {
    throw ArgumentError.value(
      message,
      'message',
      'A dispatched message must have a method',
    );
  }
  if (object.kind == JsonRpc2Kind.request && object.id == null) {
    throw ArgumentError.value(
      message,
      'message',
      'A request id must not be null',
    );
  }
  if (method == InitializeRequest.methodName ||
      method == InitializedNotification.methodName) {
    throw ArgumentError.value(
      message,
      'message',
      'Legacy lifecycle messages are not used on a request-scoped transport',
    );
  }

  // The message is delivered over an in-memory channel so the exchange runs
  // through the same Peer validation and dispatch path as a wire connection.
  final inbound = StreamController<Map<String, Object?>>();
  final outbound = StreamController<Map<String, Object?>>();
  final server = serverFactory(
    StreamChannel.withCloseGuarantee(inbound.stream, outbound.sink),
  );

  final isRequest = object.kind == JsonRpc2Kind.request;
  final response = Completer<Map<String, Object?>?>();
  final subscription = outbound.stream.listen(
    (data) {
      try {
        switch (JsonRpc2Object.fromMap(data).kind) {
          case JsonRpc2Kind.request:
            // A request from the server to the client. Nothing can answer it
            // in a single-message exchange, so fail it back to the server
            // instead of leaving its handler waiting forever. Late requests
            // from work which outlives the exchange find the connection
            // already closed.
            if (!inbound.isClosed) {
              inbound.add(
                _errorResponse(
                  JsonRpc2Request.fromMap(data).id,
                  'Server to client requests are not supported on a '
                  'request-scoped transport',
                ),
              );
            }
          case JsonRpc2Kind.notification:
            try {
              onNotification?.call(
                _withSubscriptionIdOnAcknowledgement(
                  data,
                  method,
                  message[Keys.id],
                ),
              );
            } catch (error, stackTrace) {
              // A misbehaving callback must not fail the request being
              // handled, but it should still be visible.
              Zone.current.handleUncaughtError(error, stackTrace);
            }
          case JsonRpc2Kind.response:
            if (!response.isCompleted) {
              final refusal = _inputRequiredRefusal(
                data,
                method,
                initialization,
              );
              response.complete(
                refusal == null
                    ? _withServerFields(
                      data,
                      server.implementation,
                      method,
                      initialization.protocolVersion,
                    )
                    : _rpcErrorResponse(message[Keys.id], refusal),
              );
              // A result the schema does not allow here is a bug in the
              // server. Let it reach the zone the way a frame this dispatcher
              // cannot process does. The client still gets the refusal above.
              // Asking for a capability the client left out is not a bug: a
              // server cannot know what the next client declares.
              assert(
                refusal == null || refusal.code != error_code.INTERNAL_ERROR,
                refusal.message,
              );
            }
        }
      } catch (_) {
        // The server sent a frame we could not process. Answer the request
        // before rethrowing so a caller waiting on it is not left hanging;
        // the error itself still reaches the zone, which is where a bug in
        // the server belongs.
        if (isRequest && !response.isCompleted) {
          response.complete(
            _errorResponse(
              message[Keys.id],
              'The server sent an invalid response',
            ),
          );
        }
        rethrow;
      }
    },
    onDone: () {
      if (isRequest && !response.isCompleted) {
        response.complete(
          _errorResponse(
            message[Keys.id],
            'The server closed before responding to the request',
          ),
        );
      }
    },
  );

  try {
    await server.initialize(initialization);
    server.handleInitialized();
    final rejection = await beforeDispatch?.call(server);
    if (rejection != null) {
      // The message is never added to `inbound`, so the server never sees
      // it. The `finally` block below still tears the server down exactly
      // as it would after a dispatched exchange, by closing `inbound` on an
      // empty stream.
      return isRequest ? rejection.serialize(message) : null;
    }
    if (server case final SubscriptionsSupport subscriptions
        when isRequest && method == SubscriptionsListenRequest.methodName) {
      subscriptions.nextSubscriptionId = RequestId(message[Keys.id]!);
    }
    inbound.add(message);
    if (isRequest) {
      final result = await response.future;
      if (method == SubscriptionsListenRequest.methodName &&
          result?[Keys.result] is Map<String, Object?>) {
        await server.done;
      }
      return result;
    }
    return null;
  } finally {
    await inbound.close();
    await server.done;
    await subscription.cancel();
  }
}

/// A JSON-RPC error response to the request with the given [id], carrying the
/// code, message and data of [exception].
Map<String, Object?> _rpcErrorResponse(Object? id, RpcException exception) => {
  Keys.jsonrpc: '2.0',
  Keys.id: id,
  Keys.error: {
    Keys.code: exception.code,
    Keys.message: exception.message,
    if (exception.data != null) Keys.data: exception.data,
  },
};

/// A JSON-RPC internal-error response to the request with the given [id].
Map<String, Object?> _errorResponse(Object? id, String message) =>
    _rpcErrorResponse(id, RpcException(error_code.INTERNAL_ERROR, message));

/// The error [response] has to be answered with, or `null` when the response
/// can be sent unchanged.
///
/// The 2026-07-28 revision permits an input-required result on tools/call,
/// prompts/get and resources/read. It also prohibits requests for client
/// capabilities that were not declared. See
/// https://modelcontextprotocol.io/specification/2026-07-28/basic/patterns/mrtr.
///
/// An undeclared capability is refused with [_missingClientCapability], the
/// error [MCPServer.listRoots] and [ElicitationRequestSupport.elicit] raise for
/// the same request on a connected transport, which
/// `handleStreamableHttpRequest` in `package:dart_mcp/streamable_http.dart`
/// maps to HTTP 400 while it can still send a JSON response.
///
/// A malformed result or input request gets an internal error. The client
/// capability check only runs after the wire shape has been validated.
RpcException? _inputRequiredRefusal(
  Map<String, Object?> response,
  String method,
  MCPServerInitialization initialization,
) {
  if (initialization.protocolVersion < ProtocolVersion.v2026_07_28) return null;
  final result = JsonRpc2Response.fromMap(response).result;
  if (result is! Map<String, Object?>) return null;
  if (result[Keys.resultType] != ResultTypes.inputRequired) return null;

  if (!_inputRequiredMethods.contains(method)) {
    return _malformedInputRequired(
      'on $method, which this revision allows only on '
      '${_inputRequiredMethods.map((m) => '`$m`').join(', ')}.',
    );
  }

  final hasInputRequests = result.containsKey(Keys.inputRequests);
  final hasRequestState = result.containsKey(Keys.requestState);
  if (!hasInputRequests && !hasRequestState) {
    return _malformedInputRequired(
      'without `${Keys.inputRequests}` or `${Keys.requestState}`.',
    );
  }
  if (hasRequestState && result[Keys.requestState] is! String) {
    return _malformedInputRequired(
      'whose `${Keys.requestState}` was not a string.',
    );
  }
  if (!hasInputRequests) return null;

  final requests = result[Keys.inputRequests];
  if (requests is! Map || requests.keys.any((key) => key is! String)) {
    return _malformedInputRequired(
      'whose `${Keys.inputRequests}` was not a string-keyed map.',
    );
  }
  final capabilities = initialization.clientCapabilities;
  for (final request in requests.values) {
    if (request is! Map) {
      return _malformedInputRequired(
        'whose `${Keys.inputRequests}` contained a value that was not a map.',
      );
    }
    final inputMethod = request[Keys.method];
    final params = request[Keys.params];
    if (inputMethod is! String ||
        !InputRequest.methodNames.contains(inputMethod)) {
      return _malformedInputRequired(
        'containing an input request whose method was not one of '
        '${InputRequest.methodNames.map((m) => '`$m`').join(', ')}.',
      );
    }
    switch (inputMethod) {
      case ListRootsRequest.methodName:
        if (params != null && params is! Map) {
          return _malformedInputRequired(
            'whose `${ListRootsRequest.methodName}` params were not a map.',
          );
        }
      case CreateMessageRequest.methodName:
        if (params is! Map ||
            params[Keys.messages] is! List ||
            params[Keys.maxTokens] is! int) {
          return _malformedInputRequired(
            'whose `${CreateMessageRequest.methodName}` params did not contain '
            'a messages list and integer maxTokens.',
          );
        }
      case ElicitRequest.methodName:
        if (params is! Map || params[Keys.message] is! String) {
          return _malformedInputRequired(
            'whose `${ElicitRequest.methodName}` params did not contain a '
            'message.',
          );
        }
        final mode = params[Keys.mode];
        if (mode == null || mode == ElicitationMode.form.name) {
          final schema = params[Keys.requestedSchema];
          if (schema is! Map ||
              schema[Keys.type] != JsonType.object.typeName ||
              schema[Keys.properties] is! Map) {
            return _malformedInputRequired(
              'whose form elicitation params did not contain an object schema.',
            );
          }
        } else if (mode == ElicitationMode.url.name) {
          if (params[Keys.url] is! String) {
            return _malformedInputRequired(
              'whose URL elicitation params did not contain a URL.',
            );
          }
        } else {
          return _malformedInputRequired(
            'whose elicitation mode was not '
            '`${ElicitationMode.form.name}` or `${ElicitationMode.url.name}`.',
          );
        }
    }
    final missing = _missingInputRequestCapability(
      inputMethod,
      params,
      capabilities,
    );
    if (missing != null) return missing;
  }
  return null;
}

/// The internal error refusing an `input_required` result [detail] describes.
RpcException _malformedInputRequired(String detail) => RpcException(
  error_code.INTERNAL_ERROR,
  'The server answered with `${ResultTypes.inputRequired}` $detail',
);

/// The [_missingClientCapability] error an input request made under [method]
/// has to be refused with, or `null` when [capabilities] declares what it
/// needs.
///
/// Sampling that carries `tools` or `toolChoice` needs `sampling.tools`. An
/// elicitation needs the capability for the mode it asks for. A client that
/// declared only `elicitation.url` is never asked for a form.
/// `sampling.context` is left alone: without it the schema only says a server
/// SHOULD leave `includeContext` at `none`. Refusing would go past that.
RpcException? _missingInputRequestCapability(
  String method,
  Object? params,
  ClientCapabilities capabilities,
) {
  switch (method) {
    case ListRootsRequest.methodName:
      if (capabilities.supportsRoots) return null;
      return _missingRoots;
    case CreateMessageRequest.methodName:
      final usesTools =
          params is Map &&
          (params.containsKey(Keys.tools) ||
              params.containsKey(Keys.toolChoice));
      if (!usesTools) {
        if (capabilities.supportsSampling) return null;
        return _missingSampling;
      }
      if (capabilities.supportsSamplingTools) return null;
      return _missingSamplingTools;
    case ElicitRequest.methodName:
      if (params is Map && params[Keys.mode] == ElicitationMode.url.name) {
        if (capabilities.supportsUrlElicitation) return null;
        return _missingUrlElicitation;
      }
      if (capabilities.supportsFormElicitation) return null;
      return _missingFormElicitation;
    default:
      return null;
  }
}

/// Adds [requestId] to an acknowledgement for [requestMethod].
Map<String, Object?> _withSubscriptionIdOnAcknowledgement(
  Map<String, Object?> notification,
  String requestMethod,
  Object? requestId,
) {
  if (requestMethod != SubscriptionsListenRequest.methodName ||
      notification[Keys.method] !=
          SubscriptionsAcknowledgedNotification.methodName) {
    return notification;
  }
  final params = notification[Keys.params];
  if (params is! Map<String, Object?>) return notification;
  final meta = params[Keys.meta];
  if (meta is! Map<String, Object?>?) return notification;
  return {
    ...notification,
    Keys.params: {
      ...params,
      Keys.meta: MetaWithSubscriptionId.fromMap({
        ...?meta,
        Keys.subscriptionIdMeta: requestId,
      }),
    },
  };
}

/// Returns a copy of [response] with the fields a server on this protocol
/// revision must send and the handler for [method] did not, as
/// [handleRequestScopedMessage] describes.
///
/// Returns [response] unchanged when there is nothing to add: error responses
/// have no result, and a result whose fields the handler set itself is already
/// complete.
Map<String, Object?> _withServerFields(
  Map<String, Object?> response,
  Implementation implementation,
  String method,
  ProtocolVersion protocolVersion,
) {
  final result = JsonRpc2Response.fromMap(response).result;
  if (result is! Map<String, Object?>) return response;

  // These fields are 2026-07-28 vocabulary, so a server answering an earlier
  // revision must not send any of them.
  final modern = protocolVersion >= ProtocolVersion.v2026_07_28;

  // Metadata which is not a string-keyed map is left alone rather than thrown
  // on, so a server which sends one still gets an answer.
  final meta = result[Keys.meta];
  final existingMeta = meta is Map<String, Object?>? ? meta : null;
  final addServerInfo =
      modern &&
      meta is Map<String, Object?>? &&
      existingMeta?[Keys.serverInfoMeta] == null;
  final stampSubscriptionId =
      modern &&
      method == SubscriptionsListenRequest.methodName &&
      meta is Map<String, Object?>?;
  final resultType = result[Keys.resultType];
  final addResultType = modern && resultType == null;
  // Only a complete result is cacheable. `resources/read` is the one cacheable
  // request the schema also answers with an interim result, so it is the only
  // one whose result type can excuse the hints.
  final interim =
      method == ReadResourceRequest.methodName &&
      resultType != null &&
      resultType != ResultTypes.complete;
  final cacheable = modern && !interim && _cacheableMethods.contains(method);
  // A hint the schema does not allow is not an answer, so it is replaced
  // rather than sent on. Answering with one is a bug in the server though, so
  // assert on it as well: a test fails, while a server in production still
  // gets an answer. A hint left out is not a bug, so it does not assert.
  final handlerTtlMs = result[Keys.ttlMs];
  final ttlMsAllowed = handlerTtlMs is int && handlerTtlMs >= 0;
  assert(
    !cacheable || handlerTtlMs == null || ttlMsAllowed,
    'A handler answered `${Keys.ttlMs}` with `$handlerTtlMs`, but the schema '
    'only allows a non-negative integer.',
  );
  final addTtlMs = cacheable && !ttlMsAllowed;
  final handlerScope = result[Keys.cacheScope];
  final scopeAllowed = CacheScope.values.any((s) => s.name == handlerScope);
  assert(
    !cacheable || handlerScope == null || scopeAllowed,
    'A handler answered `${Keys.cacheScope}` with `$handlerScope`, but the '
    'schema only allows '
    '${CacheScope.values.map((s) => '`${s.name}`').join(' and ')}.',
  );
  final addCacheScope = cacheable && !scopeAllowed;

  if (!addServerInfo &&
      !stampSubscriptionId &&
      !addResultType &&
      !addTtlMs &&
      !addCacheScope) {
    return response;
  }

  // With decoded channels there is no decode step between the server and this
  // dispatcher, so `result` can be the very map a handler returned. Handlers
  // may retain that map, and it may not even be modifiable (the built-in ping
  // handler's `EmptyResult()` is backed by a const map), so stamp copies
  // instead of modifying it in place.
  return {
    ...response,
    Keys.result: {
      ...result,
      if (addResultType) Keys.resultType: ResultTypes.complete,
      if (addTtlMs) Keys.ttlMs: 0,
      if (addCacheScope) Keys.cacheScope: CacheScope.private.name,
      if (addServerInfo || stampSubscriptionId)
        Keys.meta: MetaWithSubscriptionId.fromMap({
          ...?existingMeta,
          if (addServerInfo)
            Keys.serverInfoMeta: Map<String, Object?>.of(
              implementation as Map<String, Object?>,
            ),
          if (stampSubscriptionId) Keys.subscriptionIdMeta: response[Keys.id],
        }),
    },
  };
}

/// The requests a server may answer with an [InputRequiredResult].
///
/// https://modelcontextprotocol.io/specification/2026-07-28/basic/patterns/mrtr
const _inputRequiredMethods = {
  CallToolRequest.methodName,
  GetPromptRequest.methodName,
  ReadResourceRequest.methodName,
};

/// The requests whose results a server must send caching hints on.
///
/// https://modelcontextprotocol.io/specification/2026-07-28/server/utilities/caching
const _cacheableMethods = {
  DiscoverRequest.methodName,
  ListToolsRequest.methodName,
  ListPromptsRequest.methodName,
  ListResourcesRequest.methodName,
  ListResourceTemplatesRequest.methodName,
  ReadResourceRequest.methodName,
};
