// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/src/utils/constants.dart';
import 'package:json_rpc_2/error_code.dart' as error_code;
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
  ClientCapabilities capabilities, {
  ProtocolVersion protocolVersion = ProtocolVersion.v2025_11_25,
}) => handleRequestScopedMessage(
  {
    Keys.jsonrpc: '2.0',
    Keys.id: 1,
    Keys.method: CallToolRequest.methodName,
    Keys.params: {Keys.name: name},
  },
  MCPServerInitialization(
    protocolVersion: protocolVersion,
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

  test('2026-07-28 rejects sampling before capability checks', () async {
    for (final capabilities in [
      ClientCapabilities(),
      ClientCapabilities(sampling: {}),
    ]) {
      final result = await _callTool(
        'test/sample',
        capabilities,
        protocolVersion: ProtocolVersion.v2026_07_28,
      );

      final error = result![Keys.error] as Map<String, Object?>;
      expect(error[Keys.code], error_code.INTERNAL_ERROR);
      expect(
        error[Keys.message],
        contains('2026-07-28 does not have sampling/createMessage'),
      );
    }
  });

  test('2026-07-28 rejects roots before capability checks', () async {
    for (final capabilities in [
      ClientCapabilities(),
      ClientCapabilities(roots: RootsCapabilities()),
    ]) {
      final result = await _callTool(
        'test/roots',
        capabilities,
        protocolVersion: ProtocolVersion.v2026_07_28,
      );

      final error = result![Keys.error] as Map<String, Object?>;
      expect(error[Keys.code], error_code.INTERNAL_ERROR);
      expect(
        error[Keys.message],
        contains('2026-07-28 does not have roots/list'),
      );
    }
  });
}
