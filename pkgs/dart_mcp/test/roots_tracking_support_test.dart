// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:async';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/server.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  test('server can track the workspace roots if enabled', () async {
    final environment = TestEnvironment(
      TestMCPClientWithRoots(),
      (c) => TestMCPServerWithRootsTracking(channel: c),
    );
    await environment.initializeServer();

    final client = environment.client;
    final server = environment.server;

    final a = Root(uri: 'test://a', name: 'a');
    final b = Root(uri: 'test://b', name: 'b');

    /// Basic interactions, add and remove some roots.
    expect(await server.roots, isEmpty);
    expect(client.addRoot(a), isTrue);
    await pumpEventQueue();
    expect(await server.roots, [a]);
    expect(client.addRoot(b), isTrue);
    await pumpEventQueue();
    expect(await server.roots, unorderedEquals([a, b]));

    final completer = Completer<void>();
    client.waitToRespond = completer.future;
    final c = Root(uri: 'test://c', name: 'c');
    final d = Root(uri: 'test://d', name: 'd');
    expect(client.addRoot(c), isTrue);
    await pumpEventQueue();
    expect(
      server.roots,
      isA<Future>(),
      reason: 'Server is waiting to fetch new roots',
    );
    expect(
      server.roots,
      completion(unorderedEquals([b, c, d])),
      reason: 'Should not see intermediate states',
    );
    expect(client.addRoot(d), isTrue);
    await pumpEventQueue();
    expect(client.removeRoot(a), isTrue);
    await pumpEventQueue();
    completer.complete();
    client.waitToRespond = null;
    expect(await server.roots, unorderedEquals([b, c, d]));
  });
}

final class TestMCPClientWithRoots extends TestMCPClient with RootsSupport {
  // Tests can assign this to delay responses to list root requests until it
  // completes.
  Future<void>? waitToRespond;

  @override
  FutureOr<ListRootsResult> handleListRoots(ListRootsRequest request) async {
    await waitToRespond;
    return super.handleListRoots(request);
  }
}

final class TestMCPServerWithRootsTracking extends TestMCPServer
    with LoggingSupport, RootsTrackingSupport {
  TestMCPServerWithRootsTracking({required super.channel});
}
