// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'server.dart';

/// A mixin for MCP servers which serve `subscriptions/listen` requests.
///
/// Stamps the subscription id on the acknowledgement and holds the request
/// until shutdown. A `package:json_rpc_2` handler does not receive that id,
/// so a transport sets [nextSubscriptionId] before delivering the request.
/// [handleRequestScopedMessage] does. A request without one is refused.
///
/// See https://modelcontextprotocol.io/specification/2026-07-28/basic/patterns/subscriptions.
base mixin SubscriptionsSupport on MCPServer {
  /// Ends each open subscription, under the id it was opened with.
  final Map<RequestId, Completer<void>> _subscriptions = {};

  /// The first [shutdown] call, which every later one waits on.
  Completer<void>? _shutdown;

  /// The id the next `subscriptions/listen` request opens its subscription
  /// under.
  ///
  /// A handler cannot read the JSON-RPC id of the request it answers, and a
  /// subscription is named by that id. The transport serving the request sets
  /// this before delivering it. Leaving it `null` refuses the request.
  RequestId? nextSubscriptionId;

  @override
  FutureOr<void> initialize(MCPServerInitialization initialization) async {
    if (initialization.protocolVersion.methodIsValid(
      SubscriptionsListenRequest.methodName,
    )) {
      registerRequestHandler(
        SubscriptionsListenRequest.methodName,
        handleSubscriptionsListen,
      );
    }

    await super.initialize(initialization);
  }

  /// Ends every open subscription before closing the connection, so each of
  /// their requests gets the response the specification asks a server tearing
  /// a subscription down to send.
  @override
  Future<void> shutdown() async {
    if (_shutdown case final pending?) return pending.future;
    final shutdown = _shutdown = Completer<void>();
    // A later caller awaits this and sees the error; on the first call the
    // error also travels up the `rethrow` below, so nothing has to listen.
    shutdown.future.ignore();
    try {
      final open = _subscriptions.values.toList();
      _subscriptions.clear();
      for (final subscription in open) {
        if (!subscription.isCompleted) subscription.complete();
      }
      if (open.isNotEmpty && isActive) {
        // `package:json_rpc_2` writes each response in a microtask once its
        // handler returns, and drops it when the connection is already
        // closed. An event loop turn runs every pending microtask, so the
        // responses are out before `super.shutdown()` closes the connection.
        await Future<void>.delayed(Duration.zero);
      }
      await super.shutdown();
      shutdown.complete();
    } catch (error, stackTrace) {
      shutdown.completeError(error, stackTrace);
      rethrow;
    }
  }

  /// Acknowledges [request] and keeps it open until the server shuts down.
  ///
  /// The acknowledgement and the result both carry the subscription id under
  /// `io.modelcontextprotocol/subscriptionId`.
  ///
  /// Throws an [RpcException] with `-32602` if the filter is not the shape
  /// the schema describes, and `-32600` if [nextSubscriptionId] is missing
  /// or already names an open subscription.
  FutureOr<SubscriptionsListenResult> handleSubscriptionsListen(
    SubscriptionsListenRequest request,
  ) async {
    final subscriptionId = nextSubscriptionId;
    nextSubscriptionId = null;
    final fields = request as Map<String, Object?>;
    final notifications = fields[Keys.notifications];
    if (notifications is! Map<String, Object?>) {
      throw RpcException.invalidParams(
        'The `${Keys.notifications}` field got `$notifications`, but must be '
        'a JSON object.',
      );
    }
    for (final key in [
      Keys.toolsListChanged,
      Keys.promptsListChanged,
      Keys.resourcesListChanged,
    ]) {
      final value = notifications[key];
      if (notifications.containsKey(key) && value is! bool) {
        throw RpcException.invalidParams(
          'The `$key` filter got `$value`, but only allows `true`, `false`, '
          'or omission.',
        );
      }
    }
    final resourceSubscriptions = notifications[Keys.resourceSubscriptions];
    if (notifications.containsKey(Keys.resourceSubscriptions) &&
        (resourceSubscriptions is! List ||
            resourceSubscriptions.any((uri) => uri is! String))) {
      throw RpcException.invalidParams(
        'The `${Keys.resourceSubscriptions}` filter got '
        '`$resourceSubscriptions`, but must be a list of string URIs.',
      );
    }
    final requested = SubscriptionFilter.fromMap(notifications);
    final requestedResources = (resourceSubscriptions as List?)
        ?.cast<String>()
        .toList(growable: false);
    final accepted = SubscriptionFilter(
      toolsListChanged:
          requested.toolsListChanged == true &&
                  capabilities.tools?.listChanged == true
              ? true
              : null,
      promptsListChanged:
          requested.promptsListChanged == true &&
                  capabilities.prompts?.listChanged == true
              ? true
              : null,
      resourcesListChanged:
          requested.resourcesListChanged == true &&
                  capabilities.resources?.listChanged == true
              ? true
              : null,
      resourceSubscriptions:
          capabilities.resources?.subscribe == true &&
                  requestedResources?.isNotEmpty == true
              ? requestedResources
              : null,
    );
    if (subscriptionId == null) {
      throw RpcException(
        error_code.INVALID_REQUEST,
        'A `${SubscriptionsListenRequest.methodName}` subscription is named '
        'by the JSON-RPC id of the request which opens it, and this server '
        'was given no id to name this one by.',
      );
    }
    if (_subscriptions.containsKey(subscriptionId)) {
      throw RpcException(
        error_code.INVALID_REQUEST,
        'A `${SubscriptionsListenRequest.methodName}` subscription is already '
        'open under this request id.',
      );
    }
    final subscriptionEnd = Completer<void>();
    _subscriptions[subscriptionId] = subscriptionEnd;
    try {
      sendNotification(
        SubscriptionsAcknowledgedNotification.methodName,
        SubscriptionsAcknowledgedNotification(
          notifications: accepted,
          meta: MetaWithSubscriptionId(subscriptionId: subscriptionId),
        ),
      );
      await subscriptionEnd.future;
      return SubscriptionsListenResult(
        meta: MetaWithSubscriptionId(subscriptionId: subscriptionId),
      );
    } finally {
      _subscriptions.remove(subscriptionId);
    }
  }
}
