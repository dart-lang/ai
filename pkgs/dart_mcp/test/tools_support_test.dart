// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/server.dart';

import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  test('client and server can communicate', () async {
    var environment = TestEnvironment(
      TestMCPClient(),
      TestMCPServerWithTools.new,
    );
    var initializeResult = await environment.initializeServer();
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
    expect(
      result.content.single,
      isA<TextContent>().having((c) => c.text, 'text', equals('hello world!')),
    );
  });
}

class TestMCPServerWithTools extends TestMCPServer with ToolsSupport {
  TestMCPServerWithTools(super.channel) : super();

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    registerTool(
      Tool(name: 'hello world', inputSchema: InputSchema()),
      (_) => CallToolResult(content: [TextContent(text: 'hello world!')]),
    );
    return super.initialize(request);
  }
}
