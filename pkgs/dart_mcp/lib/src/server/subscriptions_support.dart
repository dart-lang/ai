// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'server.dart';

/// A mixin for MCP servers which acknowledge `subscriptions/listen` requests.
///
/// See https://modelcontextprotocol.io/specification/2026-07-28/basic/patterns/subscriptions.
base mixin SubscriptionsSupport on MCPServer {
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

  /// Acknowledges [request].
  FutureOr<SubscriptionsListenResult> handleSubscriptionsListen(
    SubscriptionsListenRequest request,
  ) {
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
    sendNotification(
      SubscriptionsAcknowledgedNotification.methodName,
      SubscriptionsAcknowledgedNotification.fromMap({
        Keys.notifications: accepted,
      }),
    );
    return SubscriptionsListenResult.fromMap({});
  }
}
