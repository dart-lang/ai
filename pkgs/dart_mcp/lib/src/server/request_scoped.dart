// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'server.dart';

/// Creates the [MCPServer] which communicates over [channel].
///
/// The returned server must be constructed on [channel], typically by passing
/// it to [MCPServer.fromStreamChannel].
typedef MCPServerFactory = MCPServer Function(StreamChannel<String> channel);

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
/// `io.modelcontextprotocol/serverInfo` result metadata key; a result which
/// already carries a server info entry, and every error response, is returned
/// unchanged. If the server closes before responding to a request, an
/// internal-error response is returned instead. The server may still be
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
  final method = message[Keys.method];
  if (method is! String) {
    throw ArgumentError.value(
      message,
      'message',
      'A dispatched message must have a string method',
    );
  }
  if (message.containsKey(Keys.id) && message[Keys.id] == null) {
    throw ArgumentError.value(
      message,
      'message',
      'A request id must not be null',
    );
  }
  if (message.containsKey(Keys.result) || message.containsKey(Keys.error)) {
    throw ArgumentError.value(
      message,
      'message',
      'A request or notification must not carry a result or error',
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

  // The message is re-encoded onto an in-memory channel so the exchange runs
  // through the same Peer validation and dispatch path as a wire connection.
  // TODO: A message-typed channel could drop the per-message encode/decode.
  // https://github.com/dart-lang/ai/issues/162
  final inbound = StreamController<String>();
  final outbound = StreamController<String>();
  final server = serverFactory(
    StreamChannel.withCloseGuarantee(inbound.stream, outbound.sink),
  );

  final isRequest = message.containsKey(Keys.id);
  final response = Completer<Map<String, Object?>?>();
  final subscription = outbound.stream.listen(
    (encoded) {
      try {
        final decoded = (jsonDecode(encoded) as Map).cast<String, Object?>();
        if (decoded.containsKey(Keys.method)) {
          if (decoded.containsKey(Keys.id)) {
            // A request from the server to the client. Nothing can answer it
            // in a single-message exchange, so fail it back to the server
            // instead of leaving its handler waiting forever. Late requests
            // from work which outlives the exchange find the connection
            // already closed.
            if (!inbound.isClosed) {
              inbound.add(
                jsonEncode(
                  _errorResponse(
                    decoded[Keys.id],
                    'Server to client requests are not supported on a '
                    'request-scoped transport',
                  ),
                ),
              );
            }
          } else {
            try {
              onNotification?.call(decoded);
            } catch (error, stackTrace) {
              // A misbehaving callback must not fail the request being
              // handled, but it should still be visible.
              Zone.current.handleUncaughtError(error, stackTrace);
            }
          }
        } else if (!response.isCompleted) {
          response.complete(_withServerInfo(decoded, server.implementation));
        }
      } catch (error, stackTrace) {
        // The server sent a frame we could not process. Never let it wedge or
        // escape the exchange: a request gets an internal error, anything else
        // surfaces as an uncaught error.
        if (isRequest && !response.isCompleted) {
          response.complete(
            _errorResponse(
              message[Keys.id],
              'The server sent an invalid response',
            ),
          );
        } else {
          Zone.current.handleUncaughtError(error, stackTrace);
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
    inbound.add(jsonEncode(message));
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

/// Returns [response] with [implementation] recorded under the reserved
/// `io.modelcontextprotocol/serverInfo` result metadata key.
///
/// Error responses have no result and are returned unchanged, as are results
/// which already carry a server info entry.
Map<String, Object?> _withServerInfo(
  Map<String, Object?> response,
  Implementation implementation,
) {
  final result = response[Keys.result];
  if (result is! Map) return response;
  final existingMeta = result[Keys.meta];
  if (existingMeta is! Map?) return response;
  final resultMap = result.cast<String, Object?>();
  final meta = existingMeta?.cast<String, Object?>() ?? <String, Object?>{};
  // Copy so the returned response does not alias the shared server info map.
  meta.putIfAbsent(
    Keys.serverInfoMeta,
    () => Map<String, Object?>.of(implementation as Map<String, Object?>),
  );
  resultMap[Keys.meta] = meta;
  return response;
}
