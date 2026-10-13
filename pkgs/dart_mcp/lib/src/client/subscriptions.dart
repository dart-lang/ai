// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'client.dart';

/// A notification and the method it arrived under on a subscription.
typedef SubscriptionNotification = ({String method, Notification params});

/// One open subscription, opened by [ServerConnection.listen].
///
/// On versions defining `subscriptions/listen`, the server stamps the [id] of
/// that request on every message it sends on the stream. On legacy versions,
/// this is a local view of the connection's list-changed and resource update
/// notifications.
///
/// See https://modelcontextprotocol.io/specification/2026-07-28/basic/patterns/subscriptions.
final class Subscription {
  /// Opens the handle for the request [ServerConnection.listen] just sent
  /// under [id]. [result] is its response.
  Subscription._(
    this._connection,
    this.id,
    Future<SubscriptionsListenResult> result,
    this._requestSent,
  ) : _resourceUris = {} {
    _requestSent.then<void>((_) {}, onError: _finishSendFailure).ignore();
    result.then<void>((_) => _finish(), onError: _finishWithError).ignore();
    // A failure reaches all three of [done], [acknowledged] and
    // [notifications], and wanting one must not raise out of the other two.
    _done.future.ignore();
    _acknowledged.future.ignore();
  }

  /// Opens the local view [ServerConnection.listen] gives on legacy versions.
  ///
  /// Acknowledges [requested] without the types [capabilities] does not
  /// support. Keys this package does not know are kept as they were.
  factory Subscription._legacy(
    ServerConnection connection,
    SubscriptionFilter requested,
    ServerCapabilities capabilities,
  ) {
    final accepted = Map.of(requested as Map<String, Object?>);
    for (final (key, supported) in [
      (Keys.toolsListChanged, capabilities.tools?.listChanged),
      (Keys.promptsListChanged, capabilities.prompts?.listChanged),
      (Keys.resourcesListChanged, capabilities.resources?.listChanged),
    ]) {
      if (accepted[key] != true || supported != true) accepted.remove(key);
    }
    if (capabilities.resources?.subscribe != true) {
      accepted.remove(Keys.resourceSubscriptions);
    }
    return Subscription._local(
      connection,
      SubscriptionFilter.fromMap(accepted),
    );
  }

  Subscription._local(this._connection, SubscriptionFilter accepted)
    : id = null,
      _requestSent = Future<void>.value(),
      _resourceUris = {...?accepted.resourceSubscriptions} {
    if (accepted.toolsListChanged == true) {
      _listenLocal(
        ToolListChangedNotification.methodName,
        _connection.toolListChanged,
      );
    }
    if (accepted.promptsListChanged == true) {
      _listenLocal(
        PromptListChangedNotification.methodName,
        _connection.promptListChanged,
      );
    }
    if (accepted.resourcesListChanged == true) {
      _listenLocal(
        ResourceListChangedNotification.methodName,
        _connection.resourceListChanged,
      );
    }
    if (_resourceUris.isEmpty) {
      _acknowledge(accepted);
    } else {
      _localListeners.add(
        _connection.resourceUpdated.listen((notification) {
          if (_resourceUris.contains(notification.uri)) {
            _forward(
              ResourceUpdatedNotification.methodName,
              notification as Map<String, Object?>,
            );
          }
        }),
      );
      Future.wait([
        for (final uri in _resourceUris.toList())
          _connection
              ._retainResource(uri)
              .then<void>((_) {}, onError: (Object _) => _refuseResource(uri)),
      ]).then<void>((_) => _acknowledgeResources(accepted)).ignore();
      _acknowledged.future.ignore();
    }
    _connection.done
        .then<void>((_) => _finish(), onError: _finishWithError)
        .ignore();
    _done.future.ignore();
  }

  /// The connection this subscription reads its notifications from.
  final ServerConnection _connection;

  /// Completes once the `subscriptions/listen` request is sent, so [close]
  /// never sends its cancellation ahead of that request. Already complete on
  /// legacy versions, where no request is sent.
  final Future<void> _requestSent;

  /// The connection streams the local view reads on legacy versions.
  final _localListeners = <StreamSubscription<Notification?>>[];

  /// The resources the local view watches on legacy versions.
  ///
  /// A resource the server refuses to subscribe to is removed.
  final Set<String> _resourceUris;

  /// The JSON-RPC ID of the `subscriptions/listen` request that opened this
  /// subscription.
  ///
  /// Every message the server sends on the stream carries it under the
  /// `io.modelcontextprotocol/subscriptionId` metadata key.
  /// On legacy versions this is `null`, because no request is sent.
  final RequestId? id;

  /// Completes [acknowledged].
  final _acknowledged = Completer<SubscriptionFilter>();

  /// Carries [notifications].
  final _notifications = StreamController<SubscriptionNotification>.broadcast();

  /// The notification types the server agreed to send.
  ///
  /// On legacy versions this is the requested filter without the types the
  /// server's capabilities do not support and the list-changed types not
  /// requested as `true`. Keys this package does not know are kept as they
  /// were.
  ///
  /// An unsupported type is left out instead of sent back as `false`, so
  /// compare this against what was asked for. On legacy versions, a URI whose
  /// `resources/subscribe` request fails is left out of
  /// `resourceSubscriptions` in the same way. Errors if the subscription ends
  /// first.
  Future<SubscriptionFilter> get acknowledged => _acknowledged.future;

  /// The notifications the server sent on this subscription.
  ///
  /// Broadcast events are not buffered, and only future events are given.
  /// Each also reaches the connection's
  /// [ServerConnection.toolListChanged], [ServerConnection.promptListChanged],
  /// [ServerConnection.resourceListChanged] and
  /// [ServerConnection.resourceUpdated].
  Stream<SubscriptionNotification> get notifications => _notifications.stream;

  /// Completes when this subscription closes locally or remotely.
  Future<void> get done => _done.future;

  /// Completes [done].
  final _done = Completer<void>();

  /// Stops this subscription without closing its connection.
  ///
  /// Also closes [notifications], which ends its listeners.
  Future<void> close() => _closing ?? _finishing ?? (_closing = _close());

  /// The first [close], if it came before this subscription started to finish.
  Future<void>? _closing;

  /// The one cleanup of this subscription, started by whichever end finishes
  /// it first.
  Future<void>? _finishing;

  /// Reports the filter on the server's acknowledgement of this subscription.
  void _acknowledge(SubscriptionFilter accepted) {
    if (!_acknowledged.isCompleted) _acknowledged.complete(accepted);
  }

  /// Acknowledges [accepted] without the resources the server refused.
  ///
  /// Keeps the order of `resourceSubscriptions` and the other keys as they
  /// were, and leaves `resourceSubscriptions` out if no resource is left.
  void _acknowledgeResources(SubscriptionFilter accepted) {
    final resourceSubscriptions = [
      for (final uri in accepted.resourceSubscriptions!)
        if (_resourceUris.contains(uri)) uri,
    ];
    final filter = {...accepted as Map<String, Object?>};
    if (resourceSubscriptions.isEmpty) {
      filter.remove(Keys.resourceSubscriptions);
    } else {
      filter[Keys.resourceSubscriptions] = resourceSubscriptions;
    }
    _acknowledge(SubscriptionFilter.fromMap(filter));
  }

  /// Stops watching [uri] after the server refused to subscribe to it.
  void _refuseResource(String uri) {
    if (_resourceUris.remove(uri)) _connection._releaseResource(uri);
  }

  void _listenLocal(String method, Stream<Notification?> notifications) {
    _localListeners.add(
      notifications.listen((notification) {
        _forward(method, (notification as Map<String, Object?>?) ?? {});
      }),
    );
  }

  /// Adds [params] under [method], once this subscription is acknowledged
  /// and still open.
  ///
  /// On versions defining `subscriptions/listen`,
  /// [ServerConnection._forwardSubscriptionNotification] has already matched
  /// [params] to this subscription's [id].
  void _forward(String method, Map<String, Object?> params) {
    if (!_acknowledged.isCompleted) return;
    if (!_notifications.isClosed) {
      _notifications.add((method: method, params: Notification(params)));
    }
  }

  Future<void> _close() async {
    final id = this.id;
    if (id == null) return _finish();
    try {
      await _requestSent;
      await _connection._cancelSubscription(id);
    } on Object catch (error, stackTrace) {
      await _finish(error: error, stackTrace: stackTrace);
      rethrow;
    }
    await _finish();
  }

  Future<void> _finish({Object? error, StackTrace? stackTrace}) =>
      _finishing ??= _finishOnce(error: error, stackTrace: stackTrace);

  Future<void> _finishOnce({Object? error, StackTrace? stackTrace}) {
    _connection._subscriptions.remove(id);
    for (final listener in _localListeners) {
      unawaited(listener.cancel());
    }
    _localListeners.clear();
    for (final uri in _resourceUris) {
      _connection._releaseResource(uri);
    }
    _resourceUris.clear();
    if (!_acknowledged.isCompleted) {
      _acknowledged.completeError(
        error ?? StateError('Closed before acknowledgement.'),
        stackTrace ?? StackTrace.current,
      );
    }
    if (error != null && !_notifications.isClosed) {
      _notifications.addError(error, stackTrace);
    }
    unawaited(_notifications.close());
    if (error == null) {
      _done.complete();
    } else {
      _done.completeError(error, stackTrace);
    }
    return Future<void>.value();
  }

  /// Reports [error] on both observable ends of the subscription and closes
  /// it.
  Future<void> _finishWithError(Object error, StackTrace stackTrace) =>
      _finish(error: error, stackTrace: stackTrace);

  Future<void> _finishSendFailure(Object error, StackTrace stackTrace) {
    final finished = _finishWithError(error, stackTrace);
    completeRequestLocally(_connection, id!);
    return finished;
  }
}
