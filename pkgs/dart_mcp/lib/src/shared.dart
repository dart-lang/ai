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

  /// The progress token of every request the peer has sent that this side has
  /// not answered yet, by JSON-RPC id.
  ///
  /// A request that asked for no progress maps to `null`. An entry goes in
  /// when the request arrives and comes out when its response leaves, so this
  /// holds exactly the requests a cancellation may still refer to.
  final _inFlightRequests = <Object, ProgressToken?>{};

  /// The ids in [_inFlightRequests] the peer has cancelled.
  final _cancelledRequests = <Object>{};

  final _cancellations = StreamController<CancelledNotification>.broadcast();

  /// The peer's cancellations of requests that were still in flight, in
  /// arrival order.
  ///
  /// [MCPBase] registers the connection's only `notifications/cancelled`
  /// handler, so a subclass that wants to log a cancellation reason, which the
  /// specification asks both parties to do, reads it here rather than
  /// registering a handler of its own. A notification naming an id this side
  /// is not currently answering never appears: the specification lets the
  /// receiver ignore an unknown id, an already answered request and a
  /// malformed notification, and this ignores all three.
  ///
  /// The request itself keeps running. What the cancellation changes is the
  /// wire: the response and any progress notification for that id stay off
  /// it, which is what the specification requires of the receiver.
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
  MCPBase(
    StreamChannel<Map<String, Object?>> channel, {
    Sink<String>? protocolLogSink,
  }) {
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
    if (p.value != null && p.value is! Map) {
      throw ArgumentError(
        'Request to $name must be a Map or null. Instead, got '
        '${p.value.runtimeType}',
      );
    }
    return impl((p.value as Map?)?.cast<String, Object?>() as T);
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
  void sendNotification(String method, [Notification? notification]) =>
      _peer.isClosed ? null : _peer.sendNotification(method, notification);

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
  ]) async =>
      ((await _peer.sendRequest(methodName, request)) as Map?)
              ?.cast<String, Object?>()
          as T;

  /// The peer may ping us at any time, and we should respond with an empty
  /// response.
  EmptyResult _handlePing([PingRequest? _]) => EmptyResult();

  /// Records the peer's cancellation of a request this side is still
  /// answering.
  ///
  /// A notification whose `requestId` is absent, or names a request that is
  /// not in flight, is ignored. That one condition covers the unknown id, the
  /// request whose response has already gone out and the malformed
  /// notification, all three of which the specification says to ignore
  /// without an error, and it keeps this side from remembering an id
  /// forever.
  void _handleCancelled(CancelledNotification notification) {
    final Object? id = notification.requestId;
    if (id == null || !_inFlightRequests.containsKey(id)) return;
    _cancelledRequests.add(id);
    _cancellations.add(notification);
  }

  /// Notes each request the peer sends on [channel] and keeps the messages for
  /// a cancelled one off it.
  ///
  /// A receiver must send no response and no further message for a request the
  /// peer cancelled, and the two kinds of message this package sends for a
  /// request are its response and the progress notifications carrying the
  /// token that request asked for. Both are dropped here, at the edge, because
  /// [Peer] answers a request whose handler returned whether or not anything
  /// cancelled it.
  ///
  /// Progress is only dropped when every in-flight request holding that token
  /// is cancelled. A peer may reuse one token across requests, and a live
  /// request still gets the progress it asked for.
  StreamChannel<Map<String, Object?>> _trackCancellations(
    StreamChannel<Map<String, Object?>> channel,
  ) => channel
      .transformStream(
        StreamTransformer.fromHandlers(
          handleData: (message, sink) {
            final object = JsonRpc2Object.fromMap(message);
            final id = object.id;
            if (object.kind == JsonRpc2Kind.request && id != null) {
              final params = message[Keys.params];
              _inFlightRequests[id] =
                  params is Map<String, Object?>
                      ? (params as Request).meta?.progressToken
                      : null;
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
                _inFlightRequests.remove(id);
                if (_cancelledRequests.remove(id)) return;
              case JsonRpc2Kind.notification:
                if (object.method != ProgressNotification.methodName) break;
                final params = message[Keys.params];
                if (params is! Map<String, Object?>) break;
                final token = (params as WithProgressToken).progressToken;
                if (token != null && _progressIsCancelled(token)) return;
              case JsonRpc2Kind.request:
                break;
            }
            sink.add(message);
          },
        ),
      );

  /// Whether [token] belongs to at least one in-flight request and every
  /// in-flight request holding it has been cancelled.
  bool _progressIsCancelled(ProgressToken token) {
    var anyCancelled = false;
    for (final MapEntry(key: id, value: requestToken)
        in _inFlightRequests.entries) {
      if (requestToken != token) continue;
      if (!_cancelledRequests.contains(id)) return false;
      anyCancelled = true;
    }
    return anyCancelled;
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
