// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:async/async.dart';
import 'package:checks/checks.dart';
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
    check(
      environment.client.capabilities.roots as Map<String, Object?>?,
    ).isNotNull().deepEquals(
      RootsCapabilities(listChanged: true) as Map<String, Object?>,
    );

    final server = environment.server;
    final events = StreamQueue(server.rootsListChanged!);

    check((await server.listRoots()).roots).isEmpty();

    final a = Root(uri: 'test://a', name: 'a');
    final a2 = Root(uri: 'test://a', name: 'a2');
    final b = Root(uri: 'test://b', name: 'b');

    check(client.addRoot(a)).isTrue();
    check(
      client.addRoot(a2),
      because: 'Roots are compared only by URI',
    ).isFalse();
    check(client.addRoot(b)).isTrue();

    check(await events.take(2)).length.equals(2);

    environment.serverConnection.sendNotification(
      RootsListChangedNotification.methodName,
    );
    check(await events.next).isNull();

    final rootsResult = await server.listRoots(ListRootsRequest());
    check(rootsResult.roots as List<Object?>).unorderedMatches([
      .it()..isA<Map<String, Object?>>().deepEquals(a as Map<String, Object?>),
      .it()..isA<Map<String, Object?>>().deepEquals(b as Map<String, Object?>),
    ]);

    check(client.removeRoot(a2)).isTrue();
    check(client.removeRoot(a)).isFalse();
    check(client.removeRoot(b)).isTrue();

    check(await events.take(2)).length.equals(2);

    check((await server.listRoots(ListRootsRequest())).roots).isEmpty();

    final hasNextFuture = check(events.hasNext).completes(.it()..isFalse());

    // Manually shutdown so the event stream can close and `hasNext` will
    // complete.
    await environment.shutdown();

    await hasNextFuture;
  });
}

final class TestMCPClientWithRoots extends TestMCPClient with RootsSupport {}
