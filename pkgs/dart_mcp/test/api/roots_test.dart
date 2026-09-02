// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:async/async.dart';
import 'package:dart_mcp/client.dart';
import 'package:test/test.dart';

import '../test_utils.dart';

void main() {
  test('server can list and subscribe to changes to roots', () async {
    final environment = TestEnvironment(
      TestMCPClientWithRoots(),
      TestMCPServer.new,
    );
    await environment.initializeServer();

    final client = environment.client;
    expect(
      environment.client.capabilities.roots,
      RootsCapabilities(listChanged: true),
    );

    final server = environment.server;
    final events = StreamQueue(server.rootsListChanged!);

    expect((await server.listRoots()).roots, isEmpty);

    final a = Root(uri: 'test://a', name: 'a');
    final a2 = Root(uri: 'test://a', name: 'a2');
    final b = Root(uri: 'test://b', name: 'b');

    expect(client.addRoot(a), isTrue);
    expect(
      client.addRoot(a2),
      isFalse,
      reason: 'Roots are compared only by URI',
    );
    expect(client.addRoot(b), isTrue);

    expect(await events.take(2), hasLength(2));

    environment.serverConnection.sendNotification(
      RootsListChangedNotification.methodName,
    );
    expect(await events.next, isNull);

    expect(
      (await server.listRoots(ListRootsRequest())).roots,
      unorderedEquals([a, b]),
    );

    expect(client.removeRoot(a2), true);
    expect(client.removeRoot(a), false);
    expect(client.removeRoot(b), true);

    expect(await events.take(2), hasLength(2));

    expect((await server.listRoots(ListRootsRequest())).roots, isEmpty);

    expect(events.hasNext, completion(false));

    // Manually shutdown so the event stream can close and `hasNext` will
    // complete.
    await environment.shutdown();
  });

  test('skips a 2026-07-28 server', () async {
    final environment = TestEnvironment(
      TestMCPClientWithRoots(),
      TestMCPServer.new,
    );
    await environment.initializeServer();

    final events = <RootsListChangedNotification?>[];
    final subscription = environment.server.rootsListChanged!.listen(
      events.add,
    );
    addTearDown(subscription.cancel);

    // The version is assignable because a transport can settle it outside the
    // handshake.
    environment.serverConnection.protocolVersion = ProtocolVersion.v2026_07_28;
    expect(
      environment.client.addRoot(Root(uri: 'test://a', name: 'a')),
      isTrue,
    );
    await pumpEventQueue();
    expect(events, isEmpty, reason: 'the revision dropped this notification');

    environment.serverConnection.protocolVersion = ProtocolVersion.v2025_11_25;
    expect(
      environment.client.addRoot(Root(uri: 'test://b', name: 'b')),
      isTrue,
    );
    await pumpEventQueue();
    expect(events, hasLength(1));
  });

  test('tells a server with no settled version', () async {
    final environment = TestEnvironment(
      TestMCPClientWithRoots(),
      TestMCPServer.new,
    );
    await environment.initializeServer();

    final events = <RootsListChangedNotification?>[];
    final subscription = environment.server.rootsListChanged!.listen(
      events.add,
    );
    addTearDown(subscription.cancel);

    environment.serverConnection.protocolVersion = null;
    expect(
      environment.client.addRoot(Root(uri: 'test://a', name: 'a')),
      isTrue,
    );
    await pumpEventQueue();

    expect(events, hasLength(1));
  });

  test('carries on past a server it skips', () async {
    final client = TestMCPClientWithRoots();
    final one = TestEnvironment(client, TestMCPServer.new);
    await one.initializeServer();
    final two = TestEnvironment(client, TestMCPServer.new);
    await two.initializeServer();

    // Skip the first connection the loop walks. A send that stops on a
    // skipped one never reaches the second.
    final (left, told) =
        client.connections.first == one.serverConnection
            ? (one, two)
            : (two, one);

    final events = <RootsListChangedNotification?>[];
    final subscription = told.server.rootsListChanged!.listen(events.add);
    addTearDown(subscription.cancel);

    left.serverConnection.protocolVersion = ProtocolVersion.v2026_07_28;
    expect(told.serverConnection.protocolVersion, ProtocolVersion.v2025_11_25);
    expect(client.addRoot(Root(uri: 'test://a', name: 'a')), isTrue);
    await pumpEventQueue();

    expect(events, hasLength(1));
  });
}

final class TestMCPClientWithRoots extends TestMCPClient with RootsSupport {}
