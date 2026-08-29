// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/src/utils/constants.dart';
import 'package:json_rpc_2/error_code.dart' as error_code;
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:test/test.dart';

import '../test_utils.dart';

/// A server on a connection which is not request scoped, the shape a stdio
/// transport for this revision has.
base class _SubscribingServer extends MCPServer with SubscriptionsSupport {
  _SubscribingServer(super.channel)
    : super.fromStreamChannel(
        implementation: Implementation(name: 'test server', version: '0.1.0'),
      );
}

void main() {
  late TestEnvironment<TestMCPClient, _SubscribingServer> environment;
  final acknowledgements = <SubscriptionsAcknowledgedNotification>[];

  setUp(() async {
    acknowledgements.clear();
    environment = TestEnvironment(TestMCPClient(), _SubscribingServer.new);
    environment.serverConnection.registerNotificationHandler(
      SubscriptionsAcknowledgedNotification.methodName,
      acknowledgements.add,
    );
    // The 2026-07-28 revision took the `initialize` handshake out, so a
    // transport for it hands the server its context directly.
    await environment.server.initialize(
      MCPServerInitialization(
        protocolVersion: ProtocolVersion.v2026_07_28,
        clientCapabilities: environment.client.capabilities,
      ),
    );
    environment.server.handleInitialized();
  });

  /// Opens a subscription the way a transport serving this method does, by
  /// naming it before the request reaches the handler.
  Future<SubscriptionsListenResult> listen({String? named}) {
    environment.server.nextSubscriptionId =
        named == null ? null : RequestId(named);
    return environment.serverConnection.sendRequest(
      SubscriptionsListenRequest.methodName,
      SubscriptionsListenRequest(
        notifications: SubscriptionFilter(toolsListChanged: true),
      ),
    );
  }

  test(
    'stamps the id on the acknowledgement and holds until shutdown',
    () async {
      final listening = listen(named: 'a');
      var completed = false;
      unawaited(listening.then((_) => completed = true));
      await pumpEventQueue(times: 20);

      expect(acknowledgements, hasLength(1));
      expect(
        acknowledgements.single.meta?[Keys.subscriptionIdMeta],
        'a',
        reason: 'the mixin stamps the id, it does not wait for HTTP to do it',
      );
      expect(
        completed,
        isFalse,
        reason: 'the listen request stays open until shutdown',
      );

      unawaited(environment.server.shutdown());
      expect(
        (await listening.timeout(const Duration(seconds: 5))).subscriptionId,
        'a',
      );
      expect(completed, isTrue);
    },
  );

  test('refuses a request the transport did not name, and stays open for the '
      'next one', () async {
    await expectLater(
      listen(),
      throwsA(
        isA<RpcException>()
            .having((e) => e.code, 'code', error_code.INVALID_REQUEST)
            .having((e) => e.data, 'data', isNot(contains('stack'))),
      ),
    );
    expect(
      acknowledgements,
      isEmpty,
      reason: 'a refused request opens nothing',
    );

    final listening = listen(named: 'a');
    await pumpEventQueue();
    expect(acknowledgements, hasLength(1));

    await environment.server.shutdown();
    expect((await listening).subscriptionId, 'a');
  });

  test('does not keep a reserved id after a malformed filter', () async {
    environment.server.nextSubscriptionId = RequestId('leaked');
    await expectLater(
      environment.serverConnection.sendRequest(
        SubscriptionsListenRequest.methodName,
        SubscriptionsListenRequest.fromMap(<String, Object?>{
          Keys.notifications: 42,
        }),
      ),
      throwsA(
        isA<RpcException>().having(
          (e) => e.code,
          'code',
          error_code.INVALID_PARAMS,
        ),
      ),
    );
    expect(
      environment.server.nextSubscriptionId,
      isNull,
      reason: 'a rejected request must not name the next one',
    );
  });

  test(
    'refuses a duplicate subscription id and keeps the first open',
    () async {
      final first = listen(named: 'a');
      await pumpEventQueue();

      await expectLater(
        listen(named: 'a'),
        throwsA(
          isA<RpcException>().having(
            (e) => e.code,
            'code',
            error_code.INVALID_REQUEST,
          ),
        ),
      );
      expect(acknowledgements, hasLength(1));

      await environment.server.shutdown();
      expect((await first).subscriptionId, 'a');
    },
  );
}
