// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/server.dart';
import 'package:test/test.dart';

import '../test_utils.dart';

void main() {
  test('client can list and invoke tools from the server', () async {
    final environment = TestEnvironment(
      TestMCPClient(),
      TestMCPServerWithTools.new,
    );
    final initializeResult = await environment.initializeServer();
    expect(
      initializeResult.capabilities.tools,
      equals(Tools(listChanged: true)),
    );

    final serverConnection = environment.serverConnection;

    final toolsResult = await serverConnection.listTools();
    expect(toolsResult.tools.length, 1);

    final tool = toolsResult.tools.single;

    final result = await serverConnection.callTool(
      CallToolRequest(name: tool.name),
    );
    expect(result.isError, isNot(true));
    expect(result.content.single, TestMCPServerWithTools.helloWorldContent);

    expect(
      await serverConnection.listTools(ListToolsRequest()),
      toolsResult,
      reason: 'can list tools with a non-null request object',
    );
  });

  test('client can subscribe to tool list updates from the server', () async {
    final environment = TestEnvironment(
      TestMCPClient(),
      TestMCPServerWithTools.new,
    );
    await environment.initializeServer();

    final serverConnection = environment.serverConnection;
    final server = environment.server;

    expect(
      serverConnection.toolListChanged,
      emitsInOrder([
        ToolListChangedNotification(),
        ToolListChangedNotification(),
      ]),
    );

    server.registerTool(
      Tool(name: 'foo', inputSchema: ObjectSchema()),
      (_) => CallToolResult(content: []),
    );

    server.unregisterTool('foo');

    // Give the notifications time to be received.
    await pumpEventQueue();

    // Need to manually close so the stream matchers can complete.
    await environment.shutdown();
  });
}

final class TestMCPServerWithTools extends TestMCPServer with ToolsSupport {
  TestMCPServerWithTools(super.channel);

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    registerTool(
      helloWorld,
      (_) => CallToolResult(content: [helloWorldContent]),
    );
    return super.initialize(request);
  }

  static final helloWorld = Tool(
    name: 'hello_world',
    description: 'Says hello world!',
    inputSchema: ObjectSchema(),
    annotations: ToolAnnotations(
      destructiveHint: false,
      idempotentHint: false,
      readOnlyHint: true,
      openWorldHint: false,
      title: 'Hello World',
    ),
  );

  static final helloWorldContent = TextContent(
    text: 'hello world!',
    annotations: Annotations(priority: 0.5, audience: [Role.user]),
  );
}
