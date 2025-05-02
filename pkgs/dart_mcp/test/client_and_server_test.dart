// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:async/async.dart';
import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/server.dart';
import 'package:json_rpc_2/error_code.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  test('client and server can communicate', () async {
    final environment = TestEnvironment(TestMCPClient(), TestMCPServer.new);
    final initializeResult = await environment.initializeServer();

    expect(initializeResult.capabilities, isEmpty);
    expect(initializeResult.instructions, environment.server.instructions);
    expect(initializeResult.protocolVersion, ProtocolVersion.latestSupported);

    expect(
      environment.serverConnection.listTools(ListToolsRequest()),
      throwsA(
        isA<RpcException>().having((e) => e.code, 'code', METHOD_NOT_FOUND),
      ),
      reason: 'The client calling unsupported methods should throw',
    );

    expect(
      environment.server.createMessage(
        CreateMessageRequest(messages: [], maxTokens: 1),
      ),
      throwsA(
        isA<RpcException>().having((e) => e.code, 'code', METHOD_NOT_FOUND),
      ),
      reason: 'The server calling unsupported methods should throw',
    );
  });

  test('client and server can capture protocol messages', () async {
    final clientLog = StreamController<String>();
    final serverLog = StreamController<String>();
    final environment = TestEnvironment(
      TestMCPClient(),
      (c) => TestMCPServer(c, protocolLogSink: serverLog.sink),
      protocolLogSink: clientLog.sink,
    );
    await environment.initializeServer();
    expect(
      clientLog.stream,
      emitsInOrder([
        allOf(startsWith('>>>'), contains('initialize')),
        allOf(startsWith('<<<'), contains('serverInfo')),
        allOf(startsWith('>>>'), contains('notifications/initialized')),
      ]),
    );
    expect(
      serverLog.stream,
      emitsInOrder([
        allOf(startsWith('<<<'), contains('initialize')),
        allOf(startsWith('>>>'), contains('serverInfo')),
        allOf(startsWith('<<<'), contains('notifications/initialized')),
      ]),
    );
  });

  test('client and server can ping each other', () async {
    final environment = TestEnvironment(TestMCPClient(), TestMCPServer.new);
    await environment.initializeServer();

    expect(await environment.serverConnection.ping(), true);
    expect(await environment.server.ping(), true);
  });

  test('client can handle ping timeouts', () async {
    final environment = TestEnvironment(TestMCPClient(), (channel) {
      channel = channel.transformStream(
        StreamTransformer.fromHandlers(
          handleData: (data, sink) async {
            // Simulate a server that doesn't respond for 100ms.
            if (data.contains('"ping"')) return;
            sink.add(data);
          },
        ),
      );
      return TestMCPServer(channel);
    });
    await environment.initializeServer();

    expect(
      await environment.serverConnection.ping(
        timeout: const Duration(milliseconds: 1),
      ),
      false,
    );
  });

  test('server can handle ping timeouts', () async {
    final environment = TestEnvironment(TestMCPClient(), (channel) {
      channel = channel.transformSink(
        StreamSinkTransformer.fromHandlers(
          handleData: (data, sink) async {
            // Simulate a client that doesn't respond.
            if (data.contains('"ping"')) return;
            sink.add(data);
          },
        ),
      );
      return TestMCPServer(channel);
    });
    await environment.initializeServer();

    expect(
      await environment.server.ping(timeout: const Duration(milliseconds: 1)),
      false,
    );
  });

  test('clients can handle progress notifications', () async {
    final environment = TestEnvironment(
      TestMCPClient(),
      InitializeProgressTestMCPServer.new,
    );
    await environment.initializeServer();
    final serverConnection = environment.serverConnection;

    final request = CallToolRequest(
      name: InitializeProgressTestMCPServer.myProgressTool.name,
      meta: MetaWithProgressToken(progressToken: ProgressToken(1337)),
    );

    expect(
      serverConnection.onProgress(request),
      emits(
        ProgressNotification(
          progressToken: request.meta!.progressToken!,
          progress: 50,
        ),
      ),
    );

    expect(
      serverConnection.onProgress(request),
      neverEmits(
        ProgressNotification(
          progressToken: request.meta!.progressToken!,
          progress: 100,
        ),
      ),
      reason: 'Should not receive progress events for completed requests',
    );

    // Ensure the subscription is set up before calling the tool.
    await pumpEventQueue();

    await serverConnection.callTool(request);

    environment.server.sendLateNotification(request.meta!.progressToken!);

    // Give the bad notification time to hit our stream.
    await pumpEventQueue();
  });

  test('servers can handle progress notifications', () async {
    final environment = TestEnvironment(
      ListRootsProgressTestMCPClient(),
      (channel) => TestMCPServer(
        channel.transformSink(
          StreamSinkTransformer<String, String>.fromHandlers(
            handleData: (data, sink) async {
              // Add a short delay when sending out a list roots request so
              // we can get progress notifications.
              if (data.contains(ListRootsRequest.methodName)) {
                await Future<void>.delayed(const Duration(milliseconds: 10));
              }
              sink.add(data);
            },
          ),
        ),
      ),
    );
    await environment.initializeServer();
    final server = environment.server;

    final request = ListRootsRequest(
      meta: MetaWithProgressToken(progressToken: ProgressToken(1337)),
    );

    // Ensure the subscription is set up before calling the tool.
    await pumpEventQueue();

    final onDone = server.listRoots(request);
    final expectedNotification = ProgressNotification(
      progressToken: request.meta!.progressToken!,
      progress: 50,
    );
    expect(server.onProgress(request), emits(expectedNotification));

    final lateNotification = ProgressNotification(
      progressToken: request.meta!.progressToken!,
      progress: 100,
    );
    expect(
      server.onProgress(request),
      neverEmits(lateNotification),
      reason: 'Should not receive progress events for completed requests',
    );

    environment.serverConnection.notifyProgress(expectedNotification);
    await onDone;
    environment.serverConnection.notifyProgress(lateNotification);

    // Give the bad notification time to hit our stream.
    await pumpEventQueue();
  });

  test('closing a server removes the connection', () async {
    final environment = TestEnvironment(TestMCPClient(), TestMCPServer.new);
    await environment.serverConnection.shutdown();
    expect(environment.client.connections, isEmpty);
  });

  group('version negotiation', () {
    test('server can downgrade the version', () async {
      final environment = TestEnvironment(
        TestMCPClient(),
        TestOldMcpServer.new,
      );

      final initializeResult = await environment.initializeServer();
      expect(initializeResult.protocolVersion, ProtocolVersion.oldestSupported);
    });

    test('server can accept a lower version', () async {
      final environment = TestEnvironment(TestMCPClient(), TestMCPServer.new);
      final initializeResult = await environment.initializeServer(
        protocolVersion: ProtocolVersion.oldestSupported,
      );
      expect(initializeResult.protocolVersion, ProtocolVersion.oldestSupported);
    });

    test(
      'client will shut down the server if version negotiation fails',
      () async {
        final environment = TestEnvironment(
          TestMCPClient(),
          TestUnrecognizedVersionMcpServer.new,
        );
        await environment.initializeServer();
        expect(environment.client.connections, isEmpty);
        expect(environment.serverConnection.isActive, false);
      },
    );
  });

  group('error handling', () {
    test('client can handle invalid protocol messages', () async {
      final protocolController = StreamController<String>();
      final environment = TestEnvironment(
        TestMCPClient(),
        TestMCPServer.new,
        protocolLogSink: protocolController.sink,
      );
      environment.serverChannel.sink.add('Just some random text');
      expect(
        protocolController.stream,
        emitsThrough(allOf(startsWith('>>>'), contains('Invalid JSON'))),
      );
      expect(environment.initializeServer(), completes);
    });

    test('server can handle invalid protocol messages', () async {
      final protocolController = StreamController<String>();
      final environment = TestEnvironment(
        TestMCPClient(),
        TestMCPServer.new,
        protocolLogSink: protocolController.sink,
      );
      environment.clientChannel.sink.add('Just some random text');
      expect(
        protocolController.stream,
        emitsThrough(allOf(startsWith('<<<'), contains('Invalid JSON'))),
      );
      expect(environment.initializeServer(), completes);
    });

    test('server exits before initialization', () {
      final client = TestMCPClient();
      final clientController = StreamController<String>();
      final serverController = StreamController<String>();
      final clientChannel = StreamChannel<String>.withGuarantees(
        clientController.stream,
        serverController.sink,
      );
      final serverChannel = StreamChannel<String>.withGuarantees(
        serverController.stream,
        clientController.sink,
      );
      final connection = client.connectServer(clientChannel);

      expect(
        connection.initialize(
          InitializeRequest(
            protocolVersion: ProtocolVersion.latestSupported,
            capabilities: ClientCapabilities(),
            clientInfo: ClientImplementation(name: '', version: ''),
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'The client closed with pending request "initialize".',
          ),
        ),
      );

      // This shuts down the channel between the client and server, so it
      // happens during the initialization request (which the server never)
      // responds to.
      serverChannel.sink.close();

      addTearDown(() {
        expect(connection.isActive, false);
        expect(client.connections, isEmpty);
      });
    });
  });
}

final class InitializeProgressTestMCPServer extends TestMCPServer
    with ToolsSupport {
  InitializeProgressTestMCPServer(super.channel);

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    registerTool(myProgressTool, _myToolImpl);
    return super.initialize(request);
  }

  Future<CallToolResult> _myToolImpl(CallToolRequest request) async {
    notifyProgress(
      ProgressNotification(
        progressToken: request.meta!.progressToken!,
        progress: 50,
      ),
    );
    // Give the client time to get the notification.
    await pumpEventQueue();

    return CallToolResult(content: []);
  }

  /// Used by the test to send a notification after the request has completed.
  void sendLateNotification(ProgressToken token) {
    notifyProgress(ProgressNotification(progressToken: token, progress: 100));
  }

  static final myProgressTool = Tool(
    name: 'progress',
    inputSchema: ObjectSchema(),
  );
}

final class ListRootsProgressTestMCPClient extends TestMCPClient
    with RootsSupport {}

final class TestOldMcpServer extends TestMCPServer {
  TestOldMcpServer(super.channel);

  @override
  Future<InitializeResult> initialize(InitializeRequest request) async {
    return (await super.initialize(request))
      ..protocolVersion = ProtocolVersion.oldestSupported;
  }
}

final class TestUnrecognizedVersionMcpServer extends TestMCPServer {
  TestUnrecognizedVersionMcpServer(super.channel);

  @override
  Future<InitializeResult> initialize(InitializeRequest request) async {
    final response = await super.initialize(request);
    (response as Map<String, Object?>)['protocolVersion'] = 'fooBar';
    return response;
  }
}
