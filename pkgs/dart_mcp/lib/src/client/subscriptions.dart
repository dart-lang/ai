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
    _done = result.then((ended) async {
      await _close();
      return ended;
    }, onError: _closeWithError);
    // A failure reaches all three of [done], [acknowledged] and
    // [notifications], and wanting one must not raise out of the other two.
    _done.ignore();
    _acknowledged.future.ignore();
  }

  /// The connection this subscription reads its notifications from.
  final ServerConnection _connection;

  /// The JSON-RPC id of the `subscriptions/listen` request that opened this
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

  /// Completes when the server ends this subscription gracefully, with the
  /// [SubscriptionsListenResult] it answers the opening request with.
  ///
  /// A transport that drops carries no such result and completes this with an
  /// error instead.
  Future<SubscriptionsListenResult> get done => _done;
  late final Future<SubscriptionsListenResult> _done;

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

  /// Releases everything this subscription holds.
  Future<void> _close() async {
    _connection._subscriptions.remove(id);
    await Future.wait([
      for (final forwarding in _forwarding) forwarding.cancel(),
    ]);
    _forwarding.clear();
    await _notifications.close();
  }

  /// Reports [error] on both observable ends of the subscription and closes
  /// it.
  Future<Never> _closeWithError(Object error, StackTrace stackTrace) async {
    if (!_acknowledged.isCompleted) {
      _acknowledged.completeError(error, stackTrace);
    }
    if (!_notifications.isClosed) {
      _notifications.addError(error, stackTrace);
    }
    await _close();
    Error.throwWithStackTrace(error, stackTrace);
  }
}
