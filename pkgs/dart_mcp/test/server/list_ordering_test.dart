// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/server.dart';
import 'package:test/test.dart';

import '../test_utils.dart';

void main() {
  test('list endpoints keep registration order across requests', () async {
    final environment = TestEnvironment(
      TestMCPClient(),
      TestMCPServerWithLists.new,
    );
    await environment.initializeServer();
    final connection = environment.serverConnection;

    for (var request = 0; request < 2; request++) {
      expect(
        [for (var tool in (await connection.listTools()).tools) tool.name],
        TestMCPServerWithLists.toolNames,
        reason: 'tools/list, request ${request + 1}',
      );
      expect(
        [
          for (var prompt in (await connection.listPrompts()).prompts)
            prompt.name,
        ],
        TestMCPServerWithLists.promptNames,
        reason: 'prompts/list, request ${request + 1}',
      );
      expect(
        [
          for (var resource in (await connection.listResources()).resources)
            resource.name,
        ],
        TestMCPServerWithLists.resourceNames,
        reason: 'resources/list, request ${request + 1}',
      );
    }
  });
}

/// A server whose tools, prompts and resources are all registered out of
/// alphabetical order.
final class TestMCPServerWithLists extends TestMCPServer
    with ToolsSupport, PromptsSupport, ResourcesSupport {
  TestMCPServerWithLists(super.channel);

  /// Registration orders which are neither ascending nor descending by name,
  /// so that sorting the entries in either direction fails the test.
  static const toolNames = ['gamma', 'alpha', 'mu', 'beta'];
  static const promptNames = ['second', 'first', 'third'];
  static const resourceNames = ['c', 'a', 'b'];

  @override
  FutureOr<void> initialize(MCPServerInitialization initialization) {
    for (final name in toolNames) {
      registerTool(
        Tool(name: name, inputSchema: ObjectSchema()),
        (_) => CallToolResult(content: []),
      );
    }
    for (final name in promptNames) {
      addPrompt(Prompt(name: name), (_) => GetPromptResult(messages: []));
    }
    for (final name in resourceNames) {
      addResource(
        Resource(name: name, uri: 'test://$name'),
        (_) => ReadResourceResult(contents: []),
      );
    }
    return super.initialize(initialization);
  }
}
