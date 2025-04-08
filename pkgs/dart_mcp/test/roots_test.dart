// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:async/async.dart';
import 'package:dart_mcp/client.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  test('server can list and subscribe to changes to roots', () async {
    var environment = TestEnvironment(
      TestMCPClientWithRoots(),
      (c) => TestMCPServer(channel: c),
    );
    await environment.initializeServer();

    final client = environment.client;
    expect(
      environment.client.capabilities.roots,
      RootsCapabilities(listChanged: true),
    );

    final server = environment.server;
    final events = StreamQueue(server.rootsListChanged!);

    expect((await server.listRoots(ListRootsRequest())).roots, isEmpty);

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
}

final class TestMCPClientWithRoots extends TestMCPClient with RootsSupport {}
