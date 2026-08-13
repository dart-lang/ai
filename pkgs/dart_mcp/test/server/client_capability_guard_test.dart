// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/src/utils/constants.dart';
import 'package:test/test.dart';

final class _RequestingServer extends MCPServer
    with LoggingSupport, ToolsSupport {
  _RequestingServer(super.channel)
    : super.fromStreamChannel(
        implementation: Implementation(name: 'test', version: '0.1.0'),
      ) {
    registerTool(Tool(name: 'test/sample', inputSchema: ObjectSchema()), (
      _,
    ) async {
      await createMessage(CreateMessageRequest(messages: [], maxTokens: 1));
      return CallToolResult(content: [TextContent(text: 'sampled')]);
    });
    registerTool(Tool(name: 'test/roots', inputSchema: ObjectSchema()), (
      _,
    ) async {
      await listRoots(ListRootsRequest());
      return CallToolResult(content: [TextContent(text: 'listed')]);
    });
  }
}

Future<Map<String, Object?>?> _callTool(
  String name,
  ClientCapabilities capabilities,
) => handleRequestScopedMessage(
  {
    Keys.jsonrpc: '2.0',
    Keys.id: 1,
    Keys.method: CallToolRequest.methodName,
    Keys.params: {Keys.name: name},
  },
  MCPServerInitialization(
    protocolVersion: ProtocolVersion.v2026_07_28,
    clientCapabilities: capabilities,
  ),
  _RequestingServer.new,
);

void main() {
  test('a tool which samples fails with the missing capability code', () async {
    final result = await _callTool('test/sample', ClientCapabilities());

    final error = result![Keys.error] as Map<String, Object?>;
    expect(error[Keys.code], McpErrorCodes.missingRequiredClientCapability);
    // In memory the data skips the JSON round trip, so it is an untyped map.
    final data = error[Keys.data] as Map;
    expect(data[Keys.requiredCapabilities], {
      Keys.sampling: <String, Object?>{},
    });
    expect(result[Keys.result], isNull);
  });

  test(
    'a tool which lists roots fails with the missing capability code',
    () async {
      final result = await _callTool('test/roots', ClientCapabilities());

      final error = result![Keys.error] as Map<String, Object?>;
      expect(error[Keys.code], McpErrorCodes.missingRequiredClientCapability);
      final data = error[Keys.data] as Map;
      expect(data[Keys.requiredCapabilities], {
        Keys.roots: <String, Object?>{},
      });
      expect(result[Keys.result], isNull);
    },
  );

  test('a declared capability reaches the transport instead', () async {
    // The request-scoped transport cannot carry a server to client request, so
    // it answers with its own error. Reaching that error is what shows the
    // guard let the request through.
    final result = await _callTool(
      'test/sample',
      ClientCapabilities(sampling: {}),
    );

    final error = result![Keys.error] as Map<String, Object?>;
    expect(
      error[Keys.code],
      isNot(McpErrorCodes.missingRequiredClientCapability),
    );
    expect(error[Keys.message], contains('request-scoped transport'));
  });
}
