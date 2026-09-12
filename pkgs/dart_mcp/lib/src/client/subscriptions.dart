// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'client.dart';

/// One open `subscriptions/listen` stream, opened by
/// [ServerConnection.listen].
///
/// The server stamps the [id] of that request on every message it sends on
/// the stream, so one connection can carry several subscriptions.
///
/// See https://modelcontextprotocol.io/specification/2026-07-28/basic/patterns/subscriptions.
final class Subscription {
  /// Opens the handle for the request [ServerConnection.listen] just sent
  /// under [id]. [result] is its response.
  Subscription._(
    this._connection,
    this.id,
    Future<SubscriptionsListenResult> result,
  ) {
    // The filter names four notification types and the connection already
    // routes each to a stream of its own, so this reads them from there
    // rather than registering handlers json_rpc_2 refuses as duplicates.
    for (final stream in <Stream<Object?>>[
      _connection.toolListChanged,
      _connection.promptListChanged,
      _connection.resourceListChanged,
      _connection.resourceUpdated,
    ]) {
      _forwarding.add(stream.listen(_forward));
    }
    result.then<void>((_) => _finish(), onError: _finishWithError).ignore();
    // A failure reaches all three of [done], [acknowledged] and
    // [notifications], and wanting one must not raise out of the other two.
    _done.future.ignore();
    _acknowledged.future.ignore();
  }

  /// The connection this subscription reads its notifications from.
  final ServerConnection _connection;

  /// The JSON-RPC ID of the `subscriptions/listen` request that opened this
  /// subscription.
  ///
  /// Every message the server sends on the stream carries it under the
  /// `io.modelcontextprotocol/subscriptionId` metadata key.
  final RequestId id;

  /// The subscriptions on the connection streams this one forwards from.
  final _forwarding = <StreamSubscription<Object?>>[];

  /// Completes [acknowledged].
  final _acknowledged = Completer<SubscriptionFilter>();

  /// Carries [notifications].
  final _notifications = StreamController<Notification>.broadcast();

  /// The notification types the server agreed to send.
  ///
  /// An unsupported type is left out rather than sent back as `false`, so
  /// compare this against what was asked for. Errors if the subscription ends
  /// first.
  Future<SubscriptionFilter> get acknowledged => _acknowledged.future;

  /// The notifications the server sent on this subscription.
  ///
  /// This is a broadcast stream, events are not buffered and only future
  /// events are given. Each also reaches the connection's
  /// [ServerConnection.toolListChanged], [ServerConnection.promptListChanged],
  /// [ServerConnection.resourceListChanged] and
  /// [ServerConnection.resourceUpdated].
  Stream<Notification> get notifications => _notifications.stream;

  /// Completes when this subscription closes locally or remotely.
  Future<void> get done => _done.future;
  final _done = Completer<void>();

  /// Stops this subscription without closing its connection.
  Future<void> close() => _closing ?? _finishing ?? (_closing = _close());
  Future<void>? _closing;

  Future<void>? _finishing;

  /// Reports the filter on the server's acknowledgement of this subscription.
  void _acknowledge(SubscriptionFilter accepted) {
    if (!_acknowledged.isCompleted) _acknowledged.complete(accepted);
  }

  /// Adds [notification] to [notifications] if it carries [id].
  void _forward(Object? notification) {
    final fields = notification as Map<String, Object?>?;
    final meta = fields?[Keys.meta];
    if (meta is! Map<String, Object?>) return;
    final sentId = meta[Keys.subscriptionIdMeta];
    if (sentId == null || RequestId(sentId) != id) return;
    if (!_notifications.isClosed) _notifications.add(Notification(fields!));
  }

  Future<void> _close() async {
    try {
      await _connection._cancelSubscription(id);
    } finally {
      await _finish();
    }
  }

  Future<void> _finish({Object? error, StackTrace? stackTrace}) =>
      _finishing ??= _finishOnce(error: error, stackTrace: stackTrace);

  Future<void> _finishOnce({Object? error, StackTrace? stackTrace}) async {
    _connection._subscriptions.remove(id);
    if (!_acknowledged.isCompleted) {
      _acknowledged.completeError(
        error ?? StateError('Closed before acknowledgement.'),
        stackTrace ?? StackTrace.current,
      );
    }
    if (error != null && !_notifications.isClosed) {
      _notifications.addError(error, stackTrace);
    }
    await Future.wait([
      for (final forwarding in _forwarding) forwarding.cancel(),
    ]);
    _forwarding.clear();
    unawaited(_notifications.close());
    if (error == null) {
      _done.complete();
    } else {
      _done.completeError(error, stackTrace);
    }
  }

  /// Reports [error] on both observable ends of the subscription and closes
  /// it.
  Future<void> _finishWithError(Object error, StackTrace stackTrace) =>
      _finish(error: error, stackTrace: stackTrace);
}
