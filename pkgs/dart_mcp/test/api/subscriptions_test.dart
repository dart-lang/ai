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
      final result = SubscriptionsListenResult(
        meta: MetaWithSubscriptionId(subscriptionId: RequestId(7)),
      );
      expect(result as Map<String, Object?>, {
        '_meta': {'io.modelcontextprotocol/subscriptionId': 7},
      });
      expect(result.subscriptionId, 7);
    });

    test('keeps the metadata it is given alongside the id', () {
      final result = SubscriptionsListenResult(
        meta: MetaWithSubscriptionId.fromMap({
          'com.example/trace': 'abc',
          'io.modelcontextprotocol/subscriptionId': RequestId('stream-1'),
        }),
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
    test('writes the filter and the subscription id it is given', () {
      final acknowledged = SubscriptionsAcknowledgedNotification(
        notifications: SubscriptionFilter(toolsListChanged: true),
        meta: MetaWithSubscriptionId(subscriptionId: RequestId(7)),
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
        meta: MetaWithSubscriptionId.fromMap({
          'com.example/trace': 'abc',
          'io.modelcontextprotocol/subscriptionId': RequestId('stream-1'),
        }),
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

  group('MetaWithSubscriptionId', () {
    test('reads back the id it was built with', () {
      final meta = MetaWithSubscriptionId(subscriptionId: RequestId('s-9'));
      expect(meta.subscriptionId, RequestId('s-9'));
    });

    test("reads the id beside a caller's own key", () {
      final meta = MetaWithSubscriptionId.fromMap({
        'com.example/trace': 'abc',
        'io.modelcontextprotocol/subscriptionId': 's-1',
      });
      expect(meta.subscriptionId, RequestId('s-1'));
      expect(meta['com.example/trace'], 'abc');
    });

    test('hands the metadata back typed on both messages', () {
      final meta = MetaWithSubscriptionId(subscriptionId: RequestId(7));
      expect(SubscriptionsListenResult(meta: meta).meta?.subscriptionId, 7);
      expect(
        SubscriptionsAcknowledgedNotification(
          notifications: SubscriptionFilter(),
          meta: meta,
        ).meta?.subscriptionId,
        7,
      );
    });

    test('has no metadata when the message carries none', () {
      expect(SubscriptionsListenResult.fromMap({}).meta, isNull);
      expect(
        SubscriptionsAcknowledgedNotification.fromMap({
          'notifications': SubscriptionFilter(),
        }).meta,
        isNull,
      );
    });

    test('throws when the id is missing', () {
      final meta = MetaWithSubscriptionId.fromMap({});
      expect(() => meta.subscriptionId, throwsArgumentError);
    });
  });
}
