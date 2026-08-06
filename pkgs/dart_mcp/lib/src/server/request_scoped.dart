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
/// [initialization] is the sole source of the per-request context.
///
/// [message] is a request if it has a non-null `id` member and a notification
/// otherwise. Returns the decoded JSON-RPC response for a request, and `null`
/// for a notification, which per JSON-RPC gets no response. A successful
/// result records the server's [MCPServer.implementation] under the reserved
/// `io.modelcontextprotocol/serverInfo` result metadata key, carries a
/// `resultType`, and, for the requests the caching rules name, carries `ttlMs`
/// and `cacheScope` unless it is an interim `resources/read` result, which is
/// not cacheable. A field the handler left out is filled in: a `resultType`
/// left `null` becomes `complete`, a `ttlMs` which is `null` becomes `0`, and
/// a `cacheScope` which is `null` becomes `private`. The dispatcher cannot
/// know when an answer goes stale, and `public` is the one guess which could
/// put a private answer in a cache shared across authorization contexts.
/// A `ttlMs` below zero or a `cacheScope` outside `public` and `private` is a
/// bug in the server: it asserts, and in a build with asserts disabled it is
/// replaced the same way a field left `null` is. None of
/// this reaches a result on an earlier revision, and every error response is
/// returned unchanged. If the server closes before responding to a request,
/// an internal-error response is returned instead. The server may still be
/// processing a notification when the returned future completes.
///
/// The returned future completes once the server responds or the exchange
/// closes; it does not time out on its own. A handler that never returns
/// leaves it pending and the server alive. To bound execution, retain the
/// server your factory creates and call [MCPServer.shutdown] on it; the
/// exchange then completes with an internal-error response.
///
/// The [ServerCapabilities] returned by [MCPServer.initialize] are
/// intentionally not surfaced: in this lifecycle clients discover
/// capabilities with `server/discover` rather than per message.
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
/// has already been torn down.
///
/// Throws an [ArgumentError] if [message] is not a JSON-RPC request or
/// notification (no string `method`, a `null` id, or a `result` or `error`
/// member), or if its method is the legacy `initialize` request or
/// `initialized` notification; classifying a message as legacy or
/// request-scoped is the transport's job. Errors thrown by [serverFactory] or
/// by [MCPServer.initialize] propagate to the caller; a server that was
/// created is shut down first.
// TODO: Support server-to-client requests once a transport can route them.
// https://github.com/dart-lang/ai/issues/162
Future<Map<String, Object?>?> handleRequestScopedMessage(
  Map<String, Object?> message,
  MCPServerInitialization initialization,
  MCPServerFactory serverFactory, {
  void Function(Map<String, Object?> notification)? onNotification,
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
              onNotification?.call(data);
            } catch (error, stackTrace) {
              // A misbehaving callback must not fail the request being
              // handled, but it should still be visible.
              Zone.current.handleUncaughtError(error, stackTrace);
            }
          case JsonRpc2Kind.response:
            if (!response.isCompleted) {
              response.complete(
                _withServerFields(
                  data,
                  server.implementation,
                  method,
                  initialization.protocolVersion,
                ),
              );
            }
        }
      } catch (error, stackTrace) {
        // The server sent a frame we could not process. Never let it wedge or
        // escape the exchange: a request gets an internal error, anything
        // else surfaces as an uncaught error. A failed assert is a bug in the
        // server rather than a frame we could not read, so it surfaces even
        // when a response still goes back; otherwise the message it carries
        // would be lost behind the internal error.
        if (error is AssertionError || !isRequest || response.isCompleted) {
          Zone.current.handleUncaughtError(error, stackTrace);
        }
        if (isRequest && !response.isCompleted) {
          response.complete(
            _errorResponse(
              message[Keys.id],
              'The server sent an invalid response',
            ),
          );
        }
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
    inbound.add(message);
    if (isRequest) return await response.future;
    return null;
  } finally {
    await inbound.close();
    await server.done;
    await subscription.cancel();
  }
}

/// A JSON-RPC internal-error response to the request with the given [id].
Map<String, Object?> _errorResponse(Object? id, String message) => {
  Keys.jsonrpc: '2.0',
  Keys.id: id,
  Keys.error: {Keys.code: error_code.INTERNAL_ERROR, Keys.message: message},
};

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

  if (!addServerInfo && !addResultType && !addTtlMs && !addCacheScope) {
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
      if (addServerInfo)
        Keys.meta: {
          ...?existingMeta,
          Keys.serverInfoMeta: Map<String, Object?>.of(
            implementation as Map<String, Object?>,
          ),
        },
    },
  };
}

/// The requests whose results a server must send caching hints on.
///
/// `server/discover` is on that list too, and joins this set when this package
/// serves it.
///
/// https://modelcontextprotocol.io/specification/2026-07-28/server/utilities/caching
const _cacheableMethods = {
  ListToolsRequest.methodName,
  ListPromptsRequest.methodName,
  ListResourcesRequest.methodName,
  ListResourceTemplatesRequest.methodName,
  ReadResourceRequest.methodName,
};
