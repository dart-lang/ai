// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:async';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/server.dart';
import 'package:test/test.dart';

import '../test_utils.dart';

void main() {
  late TestMCPClientWithRoots client;
  late TestMCPServerWithRootsTracking server;

  setUp(() async {
    final environment = TestEnvironment(
      TestMCPClientWithRoots(),
      TestMCPServerWithRootsTracking.new,
    );
    await environment.initializeServer();

    client = environment.client;
    server = environment.server;
  });

  test('server can track the workspace roots if enabled', () async {
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

  test('server normalizes absolute paths to file URIs', () async {
    // Unix style absolute path
    final unixRoot = Root(uri: '/Users/demo/todo', name: 'unix');
    client.addRoot(unixRoot);
    await pumpEventQueue();

    final roots = await server.roots;
    expect(roots.length, 1);
    expect(roots.first.uri, 'file:///Users/demo/todo');
    expect(roots.first.name, 'unix');
  });

  test('server normalizes windows drive letter paths to file URIs', () async {
    // Windows style absolute path
    final windowsRoot = Root(uri: r'C:\Users\demo\todo', name: 'windows');
    client.addRoot(windowsRoot);
    await pumpEventQueue();

    var roots = await server.roots;
    expect(roots.length, 1);
    expect(roots.first.uri, 'file:///C:/Users/demo/todo');
    expect(roots.first.name, 'windows');
    client.removeRoot(windowsRoot);

    // Existing file:// URIs should pass through untouched
    final fileRoot = Root(uri: 'file:///C:/Users/demo/todo', name: 'file_uri');
    client.addRoot(fileRoot);
    await pumpEventQueue();

    roots = await server.roots;
    expect(roots.length, 1);
    expect(roots.first.uri, 'file:///C:/Users/demo/todo');
    expect(roots.first.name, 'file_uri');
  }, testOn: 'windows');
}

final class TestMCPClientWithRoots extends TestMCPClient with RootsSupport {
  // Tests can assign this to delay responses to list root requests until it
  // completes.
  Future<void>? waitToRespond;

  @override
  FutureOr<ListRootsResult> handleListRoots([ListRootsRequest? request]) async {
    await waitToRespond;
    return super.handleListRoots(request);
  }
}

final class TestMCPServerWithRootsTracking extends TestMCPServer
    with LoggingSupport, RootsTrackingSupport {
  TestMCPServerWithRootsTracking(super.channel);
}
