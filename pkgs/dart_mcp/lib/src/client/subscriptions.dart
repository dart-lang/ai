// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'client.dart';

/// One open `subscriptions/listen` stream on a [ServerConnection].
///
/// [ServerConnection.listen] opens one. The server names it by the JSON-RPC
/// id of that request and stamps that id on every message it sends on the
/// stream, which is how a connection with several open subscriptions tells
/// them apart. Over stdio they all share one channel.
///
/// See https://modelcontextprotocol.io/specification/2026-07-28/basic/patterns/subscriptions.
final class Subscription {
  /// Opens the handle for the request [ServerConnection.listen] just sent
  /// under [id], whose response is [result].
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

  /// The JSON-RPC id of the `subscriptions/listen` request which opened this
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

  /// The notification types the server agreed to send, as its
  /// [SubscriptionsAcknowledgedNotification] reported them.
  ///
  /// A type the server does not support is left out of the filter rather than
  /// sent back as `false`, so compare this against what was asked for.
  /// Completes with an error if the subscription ends before the server
  /// acknowledges it.
  Future<SubscriptionFilter> get acknowledged => _acknowledged.future;

  /// The notifications the server sent on this subscription, each one carrying
  /// [id].
  ///
  /// This is a broadcast stream: events are not buffered, so subscribe in the
  /// same synchronous run as the [ServerConnection.listen] call. Closes when
  /// the subscription ends.
  ///
  /// These notifications also reach the connection's own
  /// [ServerConnection.toolListChanged], [ServerConnection.promptListChanged],
  /// [ServerConnection.resourceListChanged] and
  /// [ServerConnection.resourceUpdated] streams, so a caller listening to both
  /// sees each one twice.
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
