// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:async/async.dart';
import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/server.dart';
import 'package:stream_channel/stream_channel.dart';

import 'package:test/test.dart';

void main() {
  test('client and server can communicate', () async {
    final clientController = StreamController<String>.broadcast();
    final serverController = StreamController<String>.broadcast();

    final clientChannel = StreamChannel<String>.withCloseGuarantee(
      serverController.stream,
      clientController.sink.transform(
        StreamSinkTransformer.fromHandlers(
          handleData: (data, sink) {
            sink.add('$data\n');
          },
        ),
      ),
    );
    final serverChannel = StreamChannel<String>.withCloseGuarantee(
      clientController.stream,
      serverController.sink.transform(
        StreamSinkTransformer.fromHandlers(
          handleData: (data, sink) {
            sink.add('$data\n');
          },
        ),
      ),
    );

    var client = TestMCPClient();
    var server = TestMCPServer(serverChannel);
    var serverConnection = client.connectServer('test server', clientChannel);

    var initializeResult = await server.initialize(
      InitializeRequest(
        protocolVersion: protocolVersion,
        capabilities: client.capabilities,
        clientInfo: client.implementation,
      ),
    );

    expect(initializeResult.capabilities.tools, isNot(null));
    expect(initializeResult.instructions, server.instructions);

    serverConnection.notifyInitialized(InitializedNotification());

    expect(initializeResult.protocolVersion, protocolVersion);

    final toolsResult = await serverConnection.listTools();
    expect(toolsResult.tools.length, 1);

    final tool = toolsResult.tools.single;

    final result = await serverConnection.callTool(
      CallToolRequest(name: tool.name),
    );
    expect(result.isError, isNot(true));
    expect(
      result.content.single,
      isA<TextContent>().having((c) => c.text, 'text', equals('hello world!')),
    );

    await client.shutdownServer('test server');
  });
}

class TestMCPClient extends MCPClient {
  @override
  final ClientCapabilities capabilities = ClientCapabilities();

  @override
  final ClientImplementation implementation = ClientImplementation(
    name: 'test client',
    version: '0.1.0',
  );
}

class TestMCPServer extends MCPServer with ToolsSupport {
  @override
  final ServerImplementation implementation = ServerImplementation(
    name: 'test server',
    version: '0.1.0',
  );

  @override
  final instructions = 'A test server';

  TestMCPServer(super.channel) : super.fromStreamChannel();

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    registerTool(
      Tool(name: 'hello world', inputSchema: InputSchema()),
      (_) => CallToolResult(content: [TextContent(text: 'hello world!')]),
    );
    return super.initialize(request);
  }
}
