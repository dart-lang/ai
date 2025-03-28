// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:async/async.dart';
import 'package:dart_mcp/server.dart';
import 'package:json_rpc_2/error_code.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  test('client and server can communicate', () async {
    var environment = TestEnvironment(TestMCPClient(), TestMCPServer.new);
    var initializeResult = await environment.initializeServer();

    expect(initializeResult.capabilities, isEmpty);
    expect(initializeResult.instructions, environment.server.instructions);
    expect(initializeResult.protocolVersion, protocolVersion);

    expect(
      environment.serverConnection.listTools(ListToolsRequest()),
      throwsA(
        isA<RpcException>().having((e) => e.code, 'code', METHOD_NOT_FOUND),
      ),
      reason: 'Calling unsupported methods should throw',
    );
  });

  test('client and server can ping each other', () async {
    var environment = TestEnvironment(TestMCPClient(), TestMCPServer.new);
    await environment.initializeServer();

    expect(await environment.serverConnection.ping(PingRequest()), true);
    expect(await environment.server.ping(PingRequest()), true);
  });

  test('client can handle ping timeouts', () async {
    var environment = TestEnvironment(
      TestMCPClient(),
      DelayedPingTestMCPServer.new,
    );
    await environment.initializeServer();

    expect(
      await environment.serverConnection.ping(
        PingRequest(),
        timeout: const Duration(milliseconds: 1),
      ),
      false,
    );
  });

  test('server can handle ping timeouts', () async {
    var environment = TestEnvironment(TestMCPClient(), (channel) {
      channel = channel.transformSink(
        StreamSinkTransformer.fromHandlers(
          handleData: (data, sink) async {
            // Simulate a server that doesn't respond.
            if (data.contains('"ping"')) return;
          },
        ),
      );
      return TestMCPServer(channel);
    });
    await environment.initializeServer();

    expect(
      await environment.server.ping(
        PingRequest(),
        timeout: const Duration(milliseconds: 1),
      ),
      false,
    );
  });

  test('clients can handle progress notifications', () async {
    var environment = TestEnvironment(
      TestMCPClient(),
      InitializeProgressTestMCPServer.new,
    );
    await environment.initializeServer();
    var serverConnection = environment.serverConnection;

    var request = CallToolRequest(
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
}

final class DelayedPingTestMCPServer extends TestMCPServer {
  DelayedPingTestMCPServer(super.channel);

  @override
  Future<EmptyResult> handlePing(PingRequest request) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return EmptyResult();
  }
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
    inputSchema: InputSchema(),
  );
}
