// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:async/async.dart';
import 'package:checks/checks.dart';
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
    check(
      initializeResult.capabilities.tools as Map<String, Object?>,
    ).deepEquals(Tools(listChanged: true) as Map<String, Object?>);

    final serverConnection = environment.serverConnection;

    final toolsResult = await serverConnection.listTools();
    check(toolsResult.tools).has((t) => t.length, 'length').equals(2);

    final tool = toolsResult.tools.firstWhere(
      (tool) => tool.name == TestMCPServerWithTools.helloWorld.name,
    );

    final result = await serverConnection.callTool(
      CallToolRequest(name: tool.name),
    );
    check(result.isError).not((it) => it.equals(true));
    check(result.content.single as Map<String, Object?>).deepEquals(
      TestMCPServerWithTools.helloWorldContent as Map<String, Object?>,
    );

    check(
      (await serverConnection.listTools(ListToolsRequest()))
          as Map<String, Object?>,
    ).deepEquals(toolsResult as Map<String, Object?>);
  });

  test('client can subscribe to tool list updates from the server', () async {
    final environment = TestEnvironment(
      TestMCPClient(),
      TestMCPServerWithTools.new,
    );
    await environment.initializeServer();

    final serverConnection = environment.serverConnection;
    final server = environment.server;

    final toolListChangedQueue = StreamQueue(serverConnection.toolListChanged);

    server.registerTool(
      Tool(name: 'foo', inputSchema: ObjectSchema()),
      (_) => CallToolResult(content: []),
    );

    server.unregisterTool('foo');
    server.sendNotification(ToolListChangedNotification.methodName);

    // Give the notifications time to be received.
    await pumpEventQueue();

    check(
      await toolListChangedQueue.next as Map<String, Object?>,
    ).deepEquals(ToolListChangedNotification() as Map<String, Object?>);
    check(
      await toolListChangedQueue.next as Map<String, Object?>,
    ).deepEquals(ToolListChangedNotification() as Map<String, Object?>);
    check(await toolListChangedQueue.next).isNull();

    final hasNextFuture = check(
      toolListChangedQueue.hasNext,
    ).completes((it) => it.isFalse());

    // Need to manually close so the stream matchers can complete.
    await environment.shutdown();

    await hasNextFuture;
  });

  test('schema validation failure returns an error', () async {
    final environment = TestEnvironment(
      TestMCPClient(),
      TestMCPServerWithTools.new,
    );
    await environment.initializeServer();

    final serverConnection = environment.serverConnection;

    // Call with no arguments, should fail because 'message' is required.
    var result = await serverConnection.callTool(
      CallToolRequest(
        name: TestMCPServerWithTools.echo.name,
        arguments: const {},
      ),
    );
    check(result.isError).isNotNull().isTrue();
    check(result.content.single).isA<TextContent>();
    final textContent = result.content.single as TextContent;
    check(
      textContent.text,
    ).contains('Required property "message" is missing at path #root');

    // Call with wrong type for 'message'.
    result = await serverConnection.callTool(
      CallToolRequest(
        name: TestMCPServerWithTools.echo.name,
        arguments: {'message': 123},
      ),
    );
    check(result.isError).isNotNull().isTrue();
    check(result.content.single).isA<TextContent>();
    final textContent2 = result.content.single as TextContent;
    check(
      textContent2.text,
    ).contains('Value `123` is not of type `String` at path #root["message"]');
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
    registerTool(TestMCPServerWithTools.echo, TestMCPServerWithTools.echoImpl);
    return super.initialize(request);
  }

  static final echo = Tool(
    name: 'echo',
    description: 'Echoes the input',
    inputSchema: ObjectSchema(
      properties: {'message': StringSchema(description: 'The message to echo')},
      required: ['message'],
    ),
  );

  static CallToolResult echoImpl(CallToolRequest request) {
    final message = request.arguments!['message'] as String;
    return CallToolResult(content: [TextContent(text: message)]);
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
