// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// @docImport 'client/client.dart';
/// @docImport 'server/server.dart';
library;

import 'dart:async';
import 'dart:convert';

import 'package:async/async.dart' show StreamSinkTransformer;
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:meta/meta.dart';
import 'package:stream_channel/stream_channel.dart';
import 'api/api.dart';
import 'utils/constants.dart';
import 'utils/json_rpc_2_object.dart';

/// Base class for MCP server-related implementations.
///
/// Handles registering method and notification handlers, sending requests and
/// notifications, progress support, and any other shared functionality.
///
/// See also:
/// - [MCPServer] A base class to extend when implementing an MCP server.
/// - [ServerConnection] A class that represents an active server connection.
base class MCPBase {
  late final Peer _peer;

  /// The name of the associated server.
  ///
  /// Used to identify log messages.
  String get name => 'unknown';

  /// Progress controllers by token.
  ///
  /// These are created through the [onProgress] method.
  final _progressControllers =
      <ProgressToken, StreamController<ProgressNotification>>{};

  /// Every request the peer has sent that this side has not answered yet, by
  /// JSON-RPC ID.
  ///
  /// An entry goes in when the request arrives and comes out when its response
  /// leaves, so this holds exactly the requests a cancellation may still refer
  /// to.
  final _inFlightRequests = <Object, _IncomingRequest>{};

  /// The IDs in [_inFlightRequests] the peer has cancelled.
  final _cancelledRequests = <Object>{};

  /// The active request ID for each progress token.
  final _requestsByProgressToken = <ProgressToken, Object>{};

  /// Progress tokens of cancelled requests this side has already answered.
  ///
  /// The response is dropped, so the ID leaves [_inFlightRequests] while a
  /// late progress notification still names the token. Keeping that token
  /// quiet is this package's choice, not a rule the specification states.
  /// Bounded by `maxRetainedCancellations`.
  final _unownedProgressTokens = <ProgressToken>{};

  /// How many unanswered cancellations this connection retains.
  final int _maxRetainedCancellations;

  final _cancellations = StreamController<CancelledNotification>.broadcast();

  /// Connects a handler invocation to the request observed at the channel edge.
  final _requestsByParameters = Expando<_IncomingRequest>();

  /// Marks synthetic parameter maps that stand in for an omitted `params`.
  final _omittedParameters = Expando<bool>();

  /// The zone key for the request whose handler is currently running.
  final _currentRequestKey = Object();

  /// The zone in which this connection was created.
  late final Zone _connectionZone;

  /// Every `notifications/cancelled` the peer sends whose `requestId` is a
  /// JSON-RPC ID, in arrival order.
  ///
  /// [MCPBase] registers the connection's only `notifications/cancelled`
  /// handler, so a subclass that wants to log a cancellation reason, which the
  /// specification asks both parties to do, reads it here rather than
  /// registering a handler of its own.
  ///
  /// A notification naming a request this side is not answering appears here
  /// too, because the ID may belong to a request this side sent. The
  /// specification's "ignore" for an unknown ID, an already answered request
  /// and a malformed notification means no error response and no change to
  /// what goes on the wire, not that the notification is hidden from this
  /// side; the one thing dropped here is a `requestId` that is not a
  /// JSON-RPC ID at all.
  ///
  /// The request itself keeps running. What a cancellation for a request this
  /// side is answering changes is the wire: its response, progress, and other
  /// notifications stay off it.
  ///
  /// This is a "broadcast" stream, so events are not buffered and previous
  /// events will not be re-played when you subscribe.
  Stream<CancelledNotification> get cancellations => _cancellations.stream;

  /// Whether the connection with the peer is active.
  bool get isActive => !_peer.isClosed;

  /// Completes after [shutdown] is called.
  Future<void> get done => _done.future;
  final _done = Completer<void>();

  /// Initializes an MCP connection on [channel].
  ///
  /// If [protocolLogSink] is provided, all incoming and outgoing messages will
  /// be logged to it. It is the responsibility of the caller to close the
  /// sink.
  ///
  /// [maxRetainedCancellations] bounds cancelled requests whose responses have
  /// not arrived. Exceeding it closes the connection rather than forgetting a
  /// live cancellation. Zero closes on the first live cancellation.
  MCPBase(
    StreamChannel<Map<String, Object?>> channel, {
    Sink<String>? protocolLogSink,
    int maxRetainedCancellations = 1024,
  }) : _maxRetainedCancellations = RangeError.checkNotNegative(
         maxRetainedCancellations,
         'maxRetainedCancellations',
       ) {
    _connectionZone = Zone.current;
    // The channel type admits only JSON objects, so json_rpc_2 never
    // receives a batch and never writes the `List` frames its batch support
    // would answer one with.
    _peer = Peer.withoutJson(
      _trackCancellations(_maybeForwardMessages(channel, protocolLogSink)),
    );
    registerNotificationHandler(
      ProgressNotification.methodName,
      _handleProgress,
    );
    registerNotificationHandler(
      CancelledNotification.methodName,
      _handleCancelled,
    );

    registerRequestHandler(PingRequest.methodName, _handlePing);

    _peer.listen().whenComplete(shutdown);
  }

  /// Handles cleanup of all streams and other resources on shutdown.
  @mustCallSuper
  Future<void> shutdown() async {
    await _peer.close();
    _inFlightRequests.clear();
    _cancelledRequests.clear();
    _requestsByProgressToken.clear();
    _unownedProgressTokens.clear();
    final progressControllers = _progressControllers.values.toList();
    _progressControllers.clear();
    await Future.wait([
      for (var controller in progressControllers) controller.close(),
    ]);
    await _cancellations.close();
    if (!_done.isCompleted) _done.complete();
  }

  /// Registers a handler for the method [name] on this server.
  ///
  /// Any errors in [impl] will be reported to the client as JSON-RPC 2.0
  /// errors.
  void registerRequestHandler<T extends Request?, R extends Result?>(
    String name,
    FutureOr<R> Function(T) impl,
  ) => _peer.registerMethod(name, (Parameters p) {
    final parameters = p.value;
    if (parameters != null && parameters is! Map) {
      throw ArgumentError(
        'Request to $name must be a Map or null. Instead, got '
        '${parameters.runtimeType}',
      );
    }
    final typedParameters =
        parameters is Map<String, Object?> ? parameters : null;
    final request =
        typedParameters == null ? null : _requestsByParameters[typedParameters];
    final value =
        request != null && _omittedParameters[typedParameters!] == true
            ? null
            : (parameters as Map?)?.cast<String, Object?>();
    if (request == null) return impl(value as T);
    return runZoned(
      () => impl(value as T),
      zoneValues: {_currentRequestKey: request},
    );
  });

  /// Registers a notification handler named [name] on this server.
  void registerNotificationHandler<T extends Notification?>(
    String name,
    void Function(T) impl,
  ) => _peer.registerMethod(
    name,
    (Parameters? p) => impl((p?.value as Map?)?.cast<String, Object?>() as T),
  );

  /// Sends a notification to the peer.
  void sendNotification(String method, [Notification? notification]) {
    final request = Zone.current[_currentRequestKey];
    if (request is _IncomingRequest && request.cancelled) return;
    if (!_peer.isClosed) _peer.sendNotification(method, notification);
  }

  /// Runs [callback] without associating its asynchronous work with a request.
  @protected
  T runOutsideRequest<T>(T Function() callback) =>
      _connectionZone.run(callback);

  /// Captures whether the current incoming request has not been cancelled.
  @protected
  bool Function() captureIncomingRequestActivity() {
    final request = Zone.current[_currentRequestKey];
    if (request is! _IncomingRequest) return () => true;
    return () => !request.cancelled;
  }

  /// Notifies the peer of progress towards completing some request.
  void notifyProgress(ProgressNotification notification) =>
      sendNotification(ProgressNotification.methodName, notification);

  /// Sends [request] to the peer, and handles coercing the response to the
  /// type [T].
  ///
  /// Closes any progress streams for [request] once the response has been
  /// received.
  Future<T> sendRequest<T extends Result?>(
    String methodName, [
    Request? request,
  ]) async {
    try {
      return await sendRequestKeepingProgress<T>(methodName, request);
    } finally {
      await closeProgress(request);
    }
  }

  /// Sends [request] to the peer like [sendRequest] does, but leaves any
  /// progress stream for it open.
  ///
  /// This is for a caller that sends several requests under one progress
  /// token, such as an `input_required` retry. That caller owns the token and
  /// hands it back with [closeProgress] once it stops sending.
  @protected
  Future<T> sendRequestKeepingProgress<T extends Result?>(
    String methodName, [
    Request? request,
  ]) async {
    final currentRequest = Zone.current[_currentRequestKey];
    if (currentRequest is _IncomingRequest && currentRequest.cancelled) {
      throw StateError(
        'The request which started this operation was cancelled.',
      );
    }
    return ((await _peer.sendRequest(methodName, request)) as Map?)
            ?.cast<String, Object?>()
        as T;
  }

  /// The peer may ping us at any time, and we should respond with an empty
  /// response.
  EmptyResult _handlePing([PingRequest? _]) => EmptyResult();

  /// Reports the peer's cancellation on [cancellations], and remembers it if
  /// it names a request this side is still answering.
  ///
  /// A `requestId` which is not a JSON-RPC ID, an absent one included, is
  /// dropped: it can match no request in either direction. Every other
  /// cancellation is reported, including one for an ID this side never saw or
  /// has already answered, because the ID may name a request this side sent.
  /// Only an ID that is in flight here is retained. Unknown and completed IDs
  /// produce no error response and do not change what goes on the wire.
  void _handleCancelled(CancelledNotification notification) {
    // A JSON-RPC ID is a `String` or a number, so anything else cannot name a
    // request. `RequestId` is an extension type on `Object`, so the value has
    // to be tested rather than cast.
    final Object? id = notification.requestId;
    if (id == null || (id is! String && id is! num)) return;
    _cancellations.add(notification);
    if (!_inFlightRequests.containsKey(id) || _cancelledRequests.contains(id)) {
      return;
    }
    final request = _inFlightRequests[id]!;
    request.cancelled = true;
    if (_cancelledRequests.length == _maxRetainedCancellations) {
      _cancelledRequests.add(id);
      unawaited(_peer.close());
      return;
    }
    _cancelledRequests.add(id);
  }

  /// Notes each request the peer sends on [channel] and keeps the messages for
  /// a cancelled one off it.
  ///
  /// The specification asks a server receiving a cancellation to stop
  /// processing, free resources and send no response, all as SHOULDs. This
  /// package keeps the whole wire side of the request quiet: responses and
  /// progress are dropped at the channel edge, and notifications its handler
  /// sends are dropped by [sendNotification].
  ///
  /// Progress is forwarded only for the active request carrying its token.
  StreamChannel<Map<String, Object?>> _trackCancellations(
    StreamChannel<Map<String, Object?>> channel,
  ) => channel
      .transformStream(
        StreamTransformer.fromHandlers(
          handleData: (message, sink) {
            final object = JsonRpc2Object.fromMap(message);
            switch (object.kind) {
              case JsonRpc2Kind.request:
                if (_validIncomingRequest(message)) {
                  message = _trackIncomingRequest(message, object.id!);
                } else {
                  _disownProgressToken(message);
                }
              case JsonRpc2Kind.notification:
              case JsonRpc2Kind.response:
            }
            sink.add(message);
          },
        ),
      )
      .transformSink(
        StreamSinkTransformer.fromHandlers(
          handleData: (message, sink) {
            final object = JsonRpc2Object.fromMap(message);
            switch (object.kind) {
              case JsonRpc2Kind.response:
                final id = object.id;
                final token = _inFlightRequests.remove(id)?.progressToken;
                if (token != null && _requestsByProgressToken[token] == id) {
                  _requestsByProgressToken.remove(token);
                }
                if (_cancelledRequests.remove(id)) {
                  if (token != null) {
                    if (_unownedProgressTokens.length >=
                        _maxRetainedCancellations) {
                      _unownedProgressTokens.remove(
                        _unownedProgressTokens.first,
                      );
                    }
                    _unownedProgressTokens.add(token);
                  }
                  return;
                }
              case JsonRpc2Kind.notification:
                if (object.method != ProgressNotification.methodName) break;
                final params = message[Keys.params];
                if (params is! Map<String, Object?>) break;
                final token = (params as WithProgressToken).progressToken;
                if (token != null && _progressWasCancelled(token)) return;
              case JsonRpc2Kind.request:
                break;
            }
            sink.add(message);
          },
        ),
      );

  /// Records [id] and its progress token until this side answers it.
  Map<String, Object?> _trackIncomingRequest(
    Map<String, Object?> message,
    Object id,
  ) {
    final params = message[Keys.params];
    Map<String, Object?>? copiedParams;
    if (params is Map) {
      try {
        copiedParams = Map<String, Object?>.from(params);
        // A runtime-generic Map reports a non-string key as a TypeError.
        // ignore: avoid_catching_errors
      } on TypeError catch (_) {
        // A raw in-memory channel can carry a Map with a non-string key even
        // though JSON cannot. Let the RPC layer answer that malformed request
        // instead of failing this connection while copying its parameters.
      }
    }
    // A malformed request still needs an answer, so guard each metadata read.
    final meta = copiedParams?[Keys.meta];
    final token =
        meta is Map<String, Object?>
            ? MetaWithProgressToken.fromMap(meta).progressToken
            : null;
    final request = _IncomingRequest(progressToken: token);
    _inFlightRequests[id] = request;
    if (token != null) {
      // The newest request declaring a token owns it. A cancelled request keeps
      // running, so leaving the old owner in place would take the progress of a
      // live request that reuses the token.
      _unownedProgressTokens.remove(token);
      _requestsByProgressToken[token] = id;
    }

    if (copiedParams != null) {
      _requestsByParameters[copiedParams] = request;
      return {...message, Keys.params: copiedParams};
    }
    if (!message.containsKey(Keys.params)) {
      final copied = <String, Object?>{};
      _requestsByParameters[copied] = request;
      _omittedParameters[copied] = true;
      return {...message, Keys.params: copied};
    }
    return message;
  }

  /// Records the progress token of a request this side cannot track.
  ///
  /// A request whose JSON-RPC ID is not a string or a number never reaches
  /// [_inFlightRequests], so a cancellation can never name it and its progress
  /// has no owner. A later request declaring the same token takes it back.
  void _disownProgressToken(Map<String, Object?> message) {
    final params = message[Keys.params];
    if (params is! Map<String, Object?>) return;
    final meta = params[Keys.meta];
    if (meta is! Map<String, Object?>) return;
    final token = MetaWithProgressToken.fromMap(meta).progressToken;
    if (token == null) return;
    if (_unownedProgressTokens.length >= _maxRetainedCancellations) {
      _unownedProgressTokens.remove(_unownedProgressTokens.first);
    }
    _unownedProgressTokens.add(token);
  }

  /// Whether [token] belongs to a request this side answers and has cancelled.
  ///
  /// A token this connection never tracked is not one it can call cancelled.
  /// The request-scoped dispatcher builds a server per message, so a progress
  /// token can reach the sink on a connection that never saw the request it
  /// belongs to, and dropping it there would take a notification the peer is
  /// still waiting for.
  bool _progressWasCancelled(ProgressToken token) {
    if (_unownedProgressTokens.contains(token)) return true;
    final id = _requestsByProgressToken[token];
    if (id == null) return false;
    final request = _inFlightRequests[id];
    return request == null || request.cancelled;
  }

  /// Whether [message] is a request the JSON-RPC server will dispatch.
  bool _validIncomingRequest(Map<String, Object?> message) {
    if (message[Keys.jsonrpc] != '2.0' || message[Keys.method] is! String) {
      return false;
    }
    final id = message[Keys.id];
    if (id is! String && id is! num) return false;
    final params = message[Keys.params];
    return !message.containsKey(Keys.params) || params is Map || params is List;
  }

  /// Handles [ProgressNotification]s and forwards them to the streams returned
  /// by [onProgress] calls.
  void _handleProgress(ProgressNotification notification) =>
      _progressControllers[notification.progressToken]?.add(notification);

  /// A stream of progress notifications for a given [request].
  ///
  /// The [request] must contain a [ProgressToken] in its metadata (at
  /// `request.meta.progressToken`), otherwise an [ArgumentError] will be
  /// thrown.
  ///
  /// The returned stream is a "broadcast" stream, so events are not buffered
  /// and previous events will not be re-played when you subscribe.
  Stream<ProgressNotification> onProgress(Request request) {
    final token = request.meta?.progressToken;
    if (token == null) {
      throw ArgumentError.value(
        null,
        'request.meta.progressToken',
        'A progress token is required in order to track progress for a request',
      );
    }
    return (_progressControllers[token] ??=
            StreamController<ProgressNotification>.broadcast())
        .stream;
  }

  /// Closes the stream [onProgress] returned for [request], if it opened one.
  ///
  /// [sendRequest] calls this when a request is done. A caller using
  /// [sendRequestKeepingProgress] calls it once it stops sending.
  @protected
  Future<void> closeProgress(Request? request) async {
    final token = request?.meta?.progressToken;
    if (token != null) await _progressControllers.remove(token)?.close();
  }

  /// Pings the peer, and returns whether or not it responded within
  /// [timeout].
  ///
  /// The returned future completes after one of the following:
  ///
  ///   - The peer responds (returns `true`).
  ///   - The [timeout] is exceeded (returns `false`).
  ///
  /// If the timeout is reached, future values or errors from the ping request
  /// are ignored.
  Future<bool> ping({
    Duration timeout = const Duration(seconds: 1),
    PingRequest? request,
  }) => sendRequest<EmptyResult>(
    PingRequest.methodName,
    request,
  ).then((_) => true).timeout(timeout, onTimeout: () => false);

  /// If [protocolLogSink] is non-null, emits messages to it for all messages
  /// sent over [channel].
  ///
  /// This is intended to be written to a file or emitted to a user to aid in
  /// debugging protocol messages between the client and server.
  StreamChannel<Map<String, Object?>> _maybeForwardMessages(
    StreamChannel<Map<String, Object?>> channel,
    Sink<String>? protocolLogSink,
  ) {
    if (protocolLogSink == null) return channel;
    String encodeForLog(Map<String, Object?> data) {
      try {
        return jsonEncode(data);
      } catch (_) {
        // The log is diagnostic only, so a message which cannot be encoded
        // must not fail the connection.
        return '$data';
      }
    }

    return channel
        .transformStream(
          StreamTransformer.fromHandlers(
            handleData: (data, sink) {
              protocolLogSink.add('<<< ($name) ${encodeForLog(data)}\n');
              sink.add(data);
            },
          ),
        )
        .transformSink(
          StreamSinkTransformer.fromHandlers(
            handleData: (data, sink) {
              protocolLogSink.add('>>> ($name) ${encodeForLog(data)}\n');
              sink.add(data);
            },
          ),
        );
  }
}

/// Mutable wire state for one incoming request.
final class _IncomingRequest {
  final ProgressToken? progressToken;
  bool cancelled = false;

  _IncomingRequest({required this.progressToken});
}
