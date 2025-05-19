// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:async/async.dart';
import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/server.dart';
import 'package:dart_tooling_mcp_server/src/mixins/roots_fallback_support.dart';
import 'package:dart_tooling_mcp_server/src/utils/constants.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

void main() {
  late RootsTrackingSupport server;
  late ServerConnection serverConnection;
  final rootA = Root(uri: 'file:///a/');
  final rootB = Root(uri: 'file:///b/');

  late StreamController<String> clientController;
  late StreamController<String> serverController;

  setUp(() async {
    clientController = StreamController<String>();
    serverController = StreamController<String>();
    server = TestServer(
      StreamChannel.withCloseGuarantee(
        serverController.stream,
        clientController.sink,
      ),
    );
    addTearDown(() async {
      await clientController.close();
      await serverController.close();
    });
  });

  group('RootsFallbackSupport', () {
    group('when the client doesn\'t support roots', () {
      late TestClientWithoutRoots client;

      Future<void> addRoots(List<Root> roots) async {
        await serverConnection.callTool(
          CallToolRequest(
            name: RootsFallbackSupport.addRootsTool.name,
            arguments: {ParameterNames.roots: roots},
          ),
        );
      }

      Future<void> removeRoots(List<Root> roots) async {
        await serverConnection.callTool(
          CallToolRequest(
            name: RootsFallbackSupport.removeRootsTool.name,
            arguments: {
              ParameterNames.uris: [for (final root in roots) root.uri],
            },
          ),
        );
      }

      setUp(() async {
        client = TestClientWithoutRoots();
        addTearDown(client.shutdown);
        serverConnection = client.connectServer(
          StreamChannel.withCloseGuarantee(
            clientController.stream,
            serverController.sink,
          ),
        );
        await serverConnection.initialize(
          InitializeRequest(
            protocolVersion: ProtocolVersion.latestSupported,
            capabilities: client.capabilities,
            clientInfo: client.implementation,
          ),
        );
        serverConnection.notifyInitialized();
      });

      test('supportsRoots is true', () async {
        expect(server.supportsRoots, isTrue);
      });

      test('registers tools to add and remove roots', () async {
        final tools = await serverConnection.listTools(ListToolsRequest());
        expect(
          tools.tools,
          unorderedEquals([
            RootsFallbackSupport.addRootsTool,
            RootsFallbackSupport.removeRootsTool,
          ]),
        );
      });

      test('Gives roots changed notifications when tools are called', () async {
        final notifications = StreamQueue(server.rootsListChanged!);
        await addRoots([rootA]);
        expect(await notifications.hasNext, true);
        await notifications.next;

        await removeRoots([rootA]);
        expect(await notifications.hasNext, true);
        await notifications.next;
      });

      test('can add, remove, and list roots', () async {
        expect((await server.listRoots(ListRootsRequest())).roots, isEmpty);

        await addRoots([rootA, rootB]);
        expect(
          (await server.listRoots(ListRootsRequest())).roots,
          unorderedEquals([rootA, rootB]),
        );

        await removeRoots([rootB]);
        expect(
          (await server.listRoots(ListRootsRequest())).roots,
          unorderedEquals([rootA]),
        );
      });
    });

    group('when the client does support roots', () {
      late TestClientWithRoots client;

      setUp(() async {
        client = TestClientWithRoots();
        addTearDown(client.shutdown);
        serverConnection = client.connectServer(
          StreamChannel.withCloseGuarantee(
            clientController.stream,
            serverController.sink,
          ),
        );
        await serverConnection.initialize(
          InitializeRequest(
            protocolVersion: ProtocolVersion.latestSupported,
            capabilities: client.capabilities,
            clientInfo: client.implementation,
          ),
        );
        serverConnection.notifyInitialized();
      });

      test('supportsRoots is true', () async {
        expect(server.supportsRoots, isTrue);
        await server.roots; // wait for the first listRoots request to complete
      });

      test('registers no tools', () async {
        final tools = await serverConnection.listTools(ListToolsRequest());
        expect(tools.tools, isEmpty);
      });

      test('Gives roots changed notifications when roots are added', () async {
        final notifications = StreamQueue(server.rootsListChanged!);
        client.addRoot(rootA);
        expect(await notifications.hasNext, true);
        await notifications.next;

        client.removeRoot(rootA);
        expect(await notifications.hasNext, true);
        await notifications.next;
      });

      test('can add, remove, and list roots', () async {
        expect((await server.listRoots(ListRootsRequest())).roots, isEmpty);

        client
          ..addRoot(rootA)
          ..addRoot(rootB);
        expect(
          (await server.listRoots(ListRootsRequest())).roots,
          unorderedEquals([rootA, rootB]),
        );

        client.removeRoot(rootB);
        expect(
          (await server.listRoots(ListRootsRequest())).roots,
          unorderedEquals([rootA]),
        );
      });
    });
  });
}

// A test client that does not support roots
final class TestClientWithoutRoots extends MCPClient {
  TestClientWithoutRoots()
    : super(
        ClientImplementation(
          name: 'test client with no roots support',
          version: '0.1.0',
        ),
      );
}

/// A test client that supports roots
final class TestClientWithRoots extends MCPClient with RootsSupport {
  TestClientWithRoots()
    : super(
        ClientImplementation(
          name: 'test client with roots support',
          version: '0.1.0',
        ),
      );
}

/// A test server that mixes in RootsFallbackSupport
final class TestServer extends MCPServer
    with
        LoggingSupport,
        ToolsSupport,
        RootsTrackingSupport,
        RootsFallbackSupport {
  @override
  final bool forceRootsFallback;

  TestServer(
    super.channel, {
    super.protocolLogSink,
    this.forceRootsFallback = false,
  }) : super.fromStreamChannel(
         implementation: ServerImplementation(
           name: 'test server',
           version: '0.1.0',
         ),
         instructions: 'A test server with roots fallback support',
       );
}
