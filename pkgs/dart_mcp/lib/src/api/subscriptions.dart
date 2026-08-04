// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'api.dart';

/// The notification types a client opts in to on a
/// [SubscriptionsListenRequest], and the ones a server agrees to on a
/// [SubscriptionsAcknowledgedNotification].
///
/// Each type is opt-in, so a server sends only the ones it was asked for. An
/// acknowledgement carries the types the server agreed to, so a type it does
/// not support is left out of that set rather than sent back as `false`.
///
/// From the 2026-07-28 revision.
extension type SubscriptionFilter.fromMap(Map<String, Object?> _value) {
  factory SubscriptionFilter({
    bool? toolsListChanged,
    bool? promptsListChanged,
    bool? resourcesListChanged,
    List<String>? resourceSubscriptions,
  }) => SubscriptionFilter.fromMap({
    if (toolsListChanged != null) Keys.toolsListChanged: toolsListChanged,
    if (promptsListChanged != null) Keys.promptsListChanged: promptsListChanged,
    if (resourcesListChanged != null)
      Keys.resourcesListChanged: resourcesListChanged,
    if (resourceSubscriptions != null)
      Keys.resourceSubscriptions: resourceSubscriptions,
  });

  /// If true, receive [ToolListChangedNotification]s.
  bool? get toolsListChanged => _value[Keys.toolsListChanged] as bool?;

  /// If true, receive [PromptListChangedNotification]s.
  bool? get promptsListChanged => _value[Keys.promptsListChanged] as bool?;

  /// If true, receive [ResourceListChangedNotification]s.
  bool? get resourcesListChanged => _value[Keys.resourcesListChanged] as bool?;

  /// The resource URIs to receive [ResourceUpdatedNotification]s for.
  ///
  /// The 2026-07-28 revision replaces the `resources/subscribe` and
  /// `resources/unsubscribe` requests, which [SubscribeRequest] and
  /// [UnsubscribeRequest] model, with this field.
  List<String>? get resourceSubscriptions =>
      (_value[Keys.resourceSubscriptions] as List?)?.cast<String>();
}

/// Sent from the client to open a long-lived stream for the notifications
/// which do not belong to a specific request.
///
/// This replaces the HTTP GET endpoint earlier revisions used, so a stdio
/// connection and a Streamable HTTP one deliver those notifications the same
/// way.
///
/// From the 2026-07-28 revision.
extension type SubscriptionsListenRequest.fromMap(Map<String, Object?> _value)
    implements Request {
  static const methodName = 'subscriptions/listen';

  factory SubscriptionsListenRequest({
    required SubscriptionFilter notifications,
    MetaWithProgressToken? meta,
  }) => SubscriptionsListenRequest.fromMap({
    Keys.notifications: notifications,
    if (meta != null) Keys.meta: meta,
  });

  /// The notification types this request opts in to.
  SubscriptionFilter get notifications {
    final notifications = _value[Keys.notifications] as SubscriptionFilter?;
    if (notifications == null) {
      throw ArgumentError(
        'Missing ${Keys.notifications} field in $SubscriptionsListenRequest.',
      );
    }
    return notifications;
  }
}

/// The response to a [SubscriptionsListenRequest], which the server sends when
/// it ends the subscription gracefully, for example while shutting down.
///
/// The stream is long-lived, so there is no response while it is open, and an
/// abrupt transport close carries none at all. The body is empty apart from
/// the [subscriptionId] in its metadata.
///
/// From the 2026-07-28 revision.
extension type SubscriptionsListenResult.fromMap(Map<String, Object?> _value)
    implements Result {
  factory SubscriptionsListenResult({
    required RequestId subscriptionId,
    Meta? meta,
  }) => SubscriptionsListenResult.fromMap({
    Keys.meta: {...?meta?._value, Keys.subscriptionIdMeta: subscriptionId},
  });

  /// The stream this response closes.
  ///
  /// This is the JSON-RPC id of the [SubscriptionsListenRequest] which opened
  /// the stream. The notifications delivered on the stream carry it under the
  /// same `io.modelcontextprotocol/subscriptionId` metadata key, which is how
  /// a client tells its streams apart.
  RequestId get subscriptionId {
    final subscriptionId = meta?[Keys.subscriptionIdMeta];
    if (subscriptionId == null) {
      throw ArgumentError(
        'Missing ${Keys.subscriptionIdMeta} metadata in '
        '$SubscriptionsListenResult.',
      );
    }
    return RequestId(subscriptionId);
  }
}

/// Sent by the server to acknowledge a [SubscriptionsListenRequest] and report
/// the notification types it agreed to send.
///
/// This is the first message the server sends carrying the subscription's id.
/// Over stdio every subscription shares one channel, so that ordering holds
/// per subscription rather than per channel: messages belonging to other
/// subscriptions may arrive before it.
///
/// From the 2026-07-28 revision.
extension type SubscriptionsAcknowledgedNotification.fromMap(
  Map<String, Object?> _value
) implements Notification {
  static const methodName = 'notifications/subscriptions/acknowledged';

  factory SubscriptionsAcknowledgedNotification({
    required SubscriptionFilter notifications,
    Meta? meta,
  }) => SubscriptionsAcknowledgedNotification.fromMap({
    Keys.notifications: notifications,
    if (meta != null) Keys.meta: meta,
  });

  /// The notification types the server agreed to send on this stream.
  SubscriptionFilter get notifications {
    final notifications = _value[Keys.notifications] as SubscriptionFilter?;
    if (notifications == null) {
      throw ArgumentError(
        'Missing ${Keys.notifications} field in '
        '$SubscriptionsAcknowledgedNotification.',
      );
    }
    return notifications;
  }
}
