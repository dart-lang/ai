// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:async/async.dart';
import 'package:checks/checks.dart';
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

    check(initializeResult.capabilities as Map<String, Object?>).isEmpty();
    check(
      initializeResult.instructions,
    ).equals(environment.server.instructions);
    check(
      initializeResult.protocolVersion,
    ).equals(ProtocolVersion.latestSupported);

    check(environment.server.clientInfo as Map<String, Object?>?)
        .isNotNull()
        .deepEquals(environment.client.implementation as Map<String, Object?>);
    check(environment.serverConnection.serverInfo as Map<String, Object?>?)
        .isNotNull()
        .deepEquals(environment.server.implementation as Map<String, Object?>);

    await check(
      environment.serverConnection.listTools(ListToolsRequest()),
    ).throws<RpcException>(
      (it) => it.has((e) => e.code, 'code').equals(METHOD_NOT_FOUND),
    );

    await check(
      environment.server.createMessage(
        CreateMessageRequest(messages: [], maxTokens: 1),
      ),
    ).throws<RpcException>(
      (it) => it.has((e) => e.code, 'code').equals(METHOD_NOT_FOUND),
    );
  });

  test('client and server can capture protocol messages', () async {
    final clientLog = StreamController<String>();
    final serverLog = StreamController<String>();
    final clientLogQueue = StreamQueue(clientLog.stream);
    final serverLogQueue = StreamQueue(serverLog.stream);
    final environment = TestEnvironment(
      TestMCPClient(),
      (c) => TestMCPServer(c, protocolLogSink: serverLog.sink),
      protocolLogSink: clientLog.sink,
    );
    await environment.initializeServer();

    check(await clientLogQueue.next)
      ..startsWith('>>>')
      ..contains('initialize');
    check(await clientLogQueue.next)
      ..startsWith('<<<')
      ..contains('serverInfo');
    check(await clientLogQueue.next)
      ..startsWith('>>>')
      ..contains('notifications/initialized');

    check(await serverLogQueue.next)
      ..startsWith('<<<')
      ..contains('initialize');
    check(await serverLogQueue.next)
      ..startsWith('>>>')
      ..contains('serverInfo');
    check(await serverLogQueue.next)
      ..startsWith('<<<')
      ..contains('notifications/initialized');
  });

  test('client and server can ping each other', () async {
    final environment = TestEnvironment(TestMCPClient(), TestMCPServer.new);
    await environment.initializeServer();

    check(await environment.serverConnection.ping()).isTrue();
    check(await environment.server.ping()).isTrue();
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

    check(
      await environment.serverConnection.ping(
        timeout: const Duration(milliseconds: 1),
      ),
    ).isFalse();
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

    check(
      await environment.server.ping(timeout: const Duration(milliseconds: 1)),
    ).isFalse();
  });

  // Regression test for https://github.com/dart-lang/ai/issues/238.
  test('client and server can handle ping with non-null parameters', () async {
    final environment = TestEnvironment(TestMCPClient(), TestMCPServer.new);
    await environment.initializeServer();

    await check(
      environment.serverConnection.ping(request: PingRequest()),
    ).completes();
    await check(environment.server.ping(request: PingRequest())).completes();
  });

  test(
    'server can handle initialized notification with null or actual parameters',
    () async {
      for (final initializedMessage in [null, InitializedNotification()]) {
        final serverLog = StreamController<String>();
        final serverLogQueue = StreamQueue(serverLog.stream);
        final environment = TestEnvironment(
          TestMCPClient(),
          (c) => TestMCPServer(c, protocolLogSink: serverLog.sink),
        );
        await environment.serverConnection.initialize(
          InitializeRequest(
            protocolVersion: ProtocolVersion.latestSupported,
            capabilities: environment.client.capabilities,
            clientInfo: environment.client.implementation,
          ),
        );
        // Send a notification that doesn't have any parameters.
        environment.serverConnection.notifyInitialized(initializedMessage);
        final result = await environment.server.initialized;
        if (initializedMessage == null) {
          check(result).isNull();
        } else {
          check(
            result as Map<String, Object?>?,
          ).isNotNull().deepEquals(initializedMessage as Map<String, Object?>);
        }

        check(await serverLogQueue.next)
          ..startsWith('<<<')
          ..contains('initialize');
        check(await serverLogQueue.next)
          ..startsWith('>>>')
          ..contains('serverInfo');
        check(await serverLogQueue.next)
          ..startsWith('<<<')
          ..contains('notifications/initialized');

        await environment.client.shutdown();
      }
    },
  );

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

    final events = <ProgressNotification>[];
    final sub = serverConnection.onProgress(request).listen(events.add);

    // Ensure the subscription is set up before calling the tool.
    await pumpEventQueue();

    await serverConnection.callTool(request);

    environment.server.sendLateNotification(request.meta!.progressToken!);

    // Give the bad notification time to hit our stream.
    await pumpEventQueue();

    check(events as List<Object?>).deepEquals([
      ProgressNotification(
            progressToken: request.meta!.progressToken!,
            progress: 50,
          )
          as Map<String, Object?>,
    ]);

    await sub.cancel();
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

    final events = <ProgressNotification>[];
    final sub = server.onProgress(request).listen(events.add);

    // Ensure the subscription is set up before calling the tool.
    await pumpEventQueue();

    final onDone = server.listRoots(request);
    final expectedNotification = ProgressNotification(
      progressToken: request.meta!.progressToken!,
      progress: 50,
    );

    environment.serverConnection.notifyProgress(expectedNotification);
    await onDone;

    final lateNotification = ProgressNotification(
      progressToken: request.meta!.progressToken!,
      progress: 100,
    );
    environment.serverConnection.notifyProgress(lateNotification);

    // Give the bad notification time to hit our stream.
    await pumpEventQueue();

    check(
      events as List<Object?>,
    ).deepEquals([expectedNotification as Map<String, Object?>]);

    await sub.cancel();
  });

  test('closing a server removes the connection', () async {
    final environment = TestEnvironment(TestMCPClient(), TestMCPServer.new);
    await environment.serverConnection.shutdown();
    check(environment.client.connections).isEmpty();
  });

  group('version negotiation', () {
    test('client and server respect negotiated protocol version', () async {
      final environment = TestEnvironment(TestMCPClient(), TestMCPServer.new);
      final serverConnection = environment.serverConnection;
      final initializeResult = await serverConnection.initialize(
        InitializeRequest(
          protocolVersion: ProtocolVersion.oldestSupported,
          capabilities: environment.client.capabilities,
          clientInfo: environment.client.implementation,
        ),
      );
      check(
        initializeResult.protocolVersion,
      ).equals(ProtocolVersion.oldestSupported);
      check(
        serverConnection.protocolVersion,
      ).equals(ProtocolVersion.oldestSupported);
    });
    test('server can downgrade the version', () async {
      final environment = TestEnvironment(
        TestMCPClient(),
        TestOldMcpServer.new,
      );

      final initializeResult = await environment.initializeServer();
      check(
        initializeResult.protocolVersion,
      ).equals(ProtocolVersion.oldestSupported);
    });

    test('server can accept a lower version', () async {
      final environment = TestEnvironment(TestMCPClient(), TestMCPServer.new);
      final initializeResult = await environment.initializeServer(
        protocolVersion: ProtocolVersion.oldestSupported,
      );
      check(
        initializeResult.protocolVersion,
      ).equals(ProtocolVersion.oldestSupported);
    });

    test(
      'client will shut down the server if version negotiation fails',
      () async {
        final environment = TestEnvironment(
          TestMCPClient(),
          TestUnrecognizedVersionMcpServer.new,
        );
        await environment.initializeServer();
        check(environment.client.connections).isEmpty();
        check(environment.serverConnection.isActive).isFalse();
      },
    );
  });

  group('error handling', () {
    test('client can handle invalid protocol messages', () async {
      final protocolController = StreamController<String>();
      final logEvents = <String>[];
      final sub = protocolController.stream.listen(logEvents.add);
      final environment = TestEnvironment(
        TestMCPClient(),
        TestMCPServer.new,
        protocolLogSink: protocolController.sink,
      );
      environment.serverChannel.sink.add('Just some random text');

      await check(environment.initializeServer()).completes();

      await sub.cancel();
      check(logEvents).any(
        (it) => it.isA<String>()
          ..startsWith('>>>')
          ..contains('Invalid JSON'),
      );
    });

    test('server can handle invalid protocol messages', () async {
      final protocolController = StreamController<String>();
      final logEvents = <String>[];
      final sub = protocolController.stream.listen(logEvents.add);
      final environment = TestEnvironment(
        TestMCPClient(),
        TestMCPServer.new,
        protocolLogSink: protocolController.sink,
      );
      environment.clientChannel.sink.add('Just some random text');

      await check(environment.initializeServer()).completes();

      await sub.cancel();
      check(logEvents).any(
        (it) => it.isA<String>()
          ..startsWith('<<<')
          ..contains('Invalid JSON'),
      );
    });

    test('server exits before initialization', () async {
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

      final initFuture =
          check(
            connection.initialize(
              InitializeRequest(
                protocolVersion: ProtocolVersion.latestSupported,
                capabilities: ClientCapabilities(),
                clientInfo: Implementation(name: '', version: ''),
              ),
            ),
          ).throws<StateError>(
            (it) => it
                .has((e) => e.message, 'message')
                .equals('The client closed with pending request "initialize".'),
          );

      // This shuts down the channel between the client and server, so it
      // happens during the initialization request (which the server never)
      // responds to.
      unawaited(serverChannel.sink.close());

      await initFuture;

      addTearDown(() {
        check(connection.isActive).isFalse();
        check(client.connections).isEmpty();
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
