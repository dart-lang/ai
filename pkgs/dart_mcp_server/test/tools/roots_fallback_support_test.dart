// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:async/async.dart';
import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/server.dart';
import 'package:dart_mcp_server/src/mixins/roots_fallback_support.dart';
import 'package:dart_mcp_server/src/utils/names.dart';
import 'package:test/test.dart';

import '../test_harness.dart';

void main() {
  late TestHarness harness;
  final rootA = Root(uri: 'file:///a/');
  final rootB = Root(uri: 'file:///b/');

  setUp(() async {
    harness = await TestHarness.start(inProcess: true);
  });

  group('RootsFallbackSupport', () {
    Future<void> addRoots(List<String> roots) async {
      await harness.mcpServerConnection.callTool(
        CallToolRequest(
          name: ToolNames.roots.name,
          arguments: {
            ParameterNames.command: RootsCommands.add,
            ParameterNames.uris: roots,
          },
        ),
      );
    }

    Future<void> removeRoots(List<String> roots) async {
      await harness.mcpServerConnection.callTool(
        CallToolRequest(
          name: ToolNames.roots.name,
          arguments: {
            ParameterNames.command: RootsCommands.remove,
            ParameterNames.uris: roots,
          },
        ),
      );
    }

    test('registers roots tool', () async {
      final tools = await harness.mcpServerConnection.listTools(
        ListToolsRequest(),
      );
      expect(tools.tools.map((t) => t.name), contains(ToolNames.roots.name));
    });

    test('can add and remove roots', () async {
      final server = harness.serverConnectionPair.server!;

      expect(await server.roots, isEmpty);

      await addRoots([rootA.uri, rootB.uri]);
      expect(await server.roots, unorderedEquals([rootA, rootB]));

      await removeRoots([rootB.uri]);
      expect(await server.roots, unorderedEquals([rootA]));
    });

    test('can combine client and custom roots', () async {
      final server = harness.serverConnectionPair.server!;
      final notifications = StreamQueue(server.rootsListChanged);
      addTearDown(notifications.cancel);
      final clientRoot = Root(uri: 'file:///client-root/');
      final next = notifications.next;
      harness.mcpClient.addRoot(clientRoot);
      await next;
      expect(
        (await server.roots).map((r) => r.uri),
        unorderedEquals([clientRoot.uri]),
      );

      await addRoots([rootA.uri]);

      expect(
        (await server.roots).map((r) => r.uri),
        unorderedEquals([clientRoot.uri, rootA.uri]),
      );
    });

    test('Gives roots changed notifications when tools are called', () async {
      final server = harness.serverConnectionPair.server!;
      final notifications = StreamQueue(server.rootsListChanged);
      addTearDown(notifications.cancel);

      var next = notifications.next;
      await addRoots([rootA.uri]);
      await next;

      next = notifications.next;
      await removeRoots([rootA.uri]);
      await next;
    });
  });
}
