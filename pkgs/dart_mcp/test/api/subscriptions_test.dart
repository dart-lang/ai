// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_mcp/client.dart';
import 'package:test/test.dart';

void main() {
  test('the method names match the schema', () {
    expect(SubscriptionsListenRequest.methodName, 'subscriptions/listen');
    expect(
      SubscriptionsAcknowledgedNotification.methodName,
      'notifications/subscriptions/acknowledged',
    );
  });

  group('SubscriptionFilter', () {
    test('writes only the fields it is given', () {
      expect(SubscriptionFilter() as Map<String, Object?>, isEmpty);
      expect(
        SubscriptionFilter(toolsListChanged: true) as Map<String, Object?>,
        {'toolsListChanged': true},
      );
      expect(
        SubscriptionFilter(
              promptsListChanged: true,
              resourcesListChanged: true,
              resourceSubscriptions: ['file:///a'],
            )
            as Map<String, Object?>,
        {
          'promptsListChanged': true,
          'resourcesListChanged': true,
          'resourceSubscriptions': ['file:///a'],
        },
      );
      expect(
        SubscriptionFilter(resourceSubscriptions: []) as Map<String, Object?>,
        {'resourceSubscriptions': <String>[]},
      );
    });

    test('keeps an explicit false apart from an absent field', () {
      expect(
        SubscriptionFilter(toolsListChanged: false) as Map<String, Object?>,
        {'toolsListChanged': false},
      );
      expect(
        SubscriptionFilter(toolsListChanged: false).toolsListChanged,
        false,
      );
      expect(SubscriptionFilter().toolsListChanged, null);
    });

    test('reads the fields off a decoded map', () {
      final filter = SubscriptionFilter.fromMap({
        'toolsListChanged': true,
        'promptsListChanged': false,
        'resourcesListChanged': true,
        'resourceSubscriptions': <Object?>['file:///a', 'file:///b'],
      });
      expect(filter.toolsListChanged, true);
      expect(filter.promptsListChanged, false);
      expect(filter.resourcesListChanged, true);
      expect(filter.resourceSubscriptions, ['file:///a', 'file:///b']);

      final absent = SubscriptionFilter.fromMap({});
      expect(absent.toolsListChanged, null);
      expect(absent.promptsListChanged, null);
      expect(absent.resourcesListChanged, null);
      expect(absent.resourceSubscriptions, null);
    });
  });

  group('SubscriptionsListenRequest', () {
    test('writes the filter it is given', () {
      final request = SubscriptionsListenRequest(
        notifications: SubscriptionFilter(toolsListChanged: true),
      );
      expect(request as Map<String, Object?>, {
        'notifications': {'toolsListChanged': true},
      });
      expect(request.notifications.toolsListChanged, true);
    });

    test('throws when the filter is missing', () {
      expect(
        () => SubscriptionsListenRequest.fromMap({}).notifications,
        throwsArgumentError,
      );
    });
  });

  group('SubscriptionsListenResult', () {
    test('writes the subscription id into the result metadata', () {
      final result = SubscriptionsListenResult(subscriptionId: RequestId(7));
      expect(result as Map<String, Object?>, {
        '_meta': {'io.modelcontextprotocol/subscriptionId': 7},
      });
      expect(result.subscriptionId, 7);
    });

    test('keeps the metadata it is given alongside the id', () {
      final result = SubscriptionsListenResult(
        subscriptionId: RequestId('stream-1'),
        meta: Meta.fromMap({'com.example/trace': 'abc'}),
      );
      expect(result as Map<String, Object?>, {
        '_meta': {
          'com.example/trace': 'abc',
          'io.modelcontextprotocol/subscriptionId': 'stream-1',
        },
      });
      expect(result.subscriptionId, 'stream-1');
    });

    test('throws when the subscription id is missing', () {
      expect(
        () => SubscriptionsListenResult.fromMap({}).subscriptionId,
        throwsArgumentError,
      );
      expect(
        () =>
            SubscriptionsListenResult.fromMap({
              '_meta': <String, Object?>{},
            }).subscriptionId,
        throwsArgumentError,
      );
    });
  });

  group('SubscriptionsAcknowledgedNotification', () {
    test('writes the filter it is given', () {
      final acknowledged = SubscriptionsAcknowledgedNotification(
        notifications: SubscriptionFilter(toolsListChanged: true),
        subscriptionId: RequestId(7),
      );
      expect(acknowledged as Map<String, Object?>, {
        'notifications': {'toolsListChanged': true},
        '_meta': {'io.modelcontextprotocol/subscriptionId': 7},
      });
      expect(acknowledged.notifications.toolsListChanged, true);
      expect(acknowledged.subscriptionId, 7);
    });

    test('keeps the metadata it is given alongside the id', () {
      final acknowledged = SubscriptionsAcknowledgedNotification(
        notifications: SubscriptionFilter(),
        subscriptionId: RequestId('stream-1'),
        meta: Meta.fromMap({'com.example/trace': 'abc'}),
      );
      expect((acknowledged as Map<String, Object?>)['_meta'], {
        'com.example/trace': 'abc',
        'io.modelcontextprotocol/subscriptionId': 'stream-1',
      });
      expect(acknowledged.subscriptionId, 'stream-1');
    });

    test('throws when the filter is missing', () {
      expect(
        () => SubscriptionsAcknowledgedNotification.fromMap({}).notifications,
        throwsArgumentError,
      );
    });

    test('throws when the subscription id is missing', () {
      expect(
        () => SubscriptionsAcknowledgedNotification.fromMap({}).subscriptionId,
        throwsArgumentError,
      );
      expect(
        () =>
            SubscriptionsAcknowledgedNotification.fromMap({
              '_meta': <String, Object?>{},
            }).subscriptionId,
        throwsArgumentError,
      );
    });
  });
}
