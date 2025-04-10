// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:meta/meta.dart';

import 'api/api.dart';

/// Base class for both client and server implementations.
///
/// Handles registering method and notification handlers, sending requests and
/// notifications, progress support, and any other shared functionality.
base class MCPBase {
  final Peer _peer;

  /// Progress controllers by token.
  ///
  /// These are created through the [onProgress] method.
  final _progressControllers =
      <ProgressToken, StreamController<ProgressNotification>>{};

  /// Whether the connection with the peer is active.
  bool get isActive => !_peer.isClosed;

  MCPBase(this._peer) {
    registerNotificationHandler(
      ProgressNotification.methodName,
      _handleProgress,
    );

    registerRequestHandler(PingRequest.methodName, _handlePing);

    _peer.listen();
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
  }

  /// Registers a handler for the method [name] on this server.
  ///
  /// Any errors in [impl] will be reported to the client as JSON-RPC 2.0
  /// errors.
  void registerRequestHandler<T extends Request?, R extends Result?>(
    String name,
    FutureOr<R> Function(T) impl,
  ) => _peer.registerMethod(
    name,
    (Parameters p) => impl((p.value as Map?)?.cast<String, Object?>() as T),
  );

  /// Registers a notification handler named [name] on this server.
  void registerNotificationHandler<T extends Notification?>(
    String name,
    void Function(T) impl,
  ) => _peer.registerMethod(
    name,
    (Parameters p) => impl((p.value as Map?)?.cast<String, Object?>() as T),
  );

  /// Sends a notification to the peer.
  void sendNotification(String method, [Notification? notification]) =>
      _peer.sendNotification(method, notification);

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
      return ((await _peer.sendRequest(methodName, request)) as Map?)
              ?.cast<String, Object?>()
          as T;
    } finally {
      final token = request?.meta?.progressToken;
      if (token != null) {
        await _progressControllers.remove(token)?.close();
      }
    }
  }

  /// The peer may ping us at any time, and we should respond with an empty
  /// response.
  ///
  /// Note that [PingRequest] is always actually just `null`.
  EmptyResult _handlePing([PingRequest? _]) => EmptyResult();

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
  Future<bool> ping({Duration timeout = const Duration(seconds: 1)}) =>
      sendRequest<EmptyResult>(
        PingRequest.methodName,
        null,
      ).then((_) => true).timeout(timeout, onTimeout: () => false);
}
