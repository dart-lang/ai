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
      request,
    ) {
      if (request.inputResponses?.containsKey('answer') ?? false) {
        return CallToolResult(content: [TextContent(text: 'sampled')]);
      }
      return InputRequiredResult(
        inputRequests: {
          'answer': InputRequest.sample(
            CreateMessageRequest(messages: [], maxTokens: 1),
          ),
        },
      );
    });
    registerTool(Tool(name: 'test/roots', inputSchema: ObjectSchema()), (
      request,
    ) {
      if (request.inputResponses?.containsKey('answer') ?? false) {
        return CallToolResult(content: [TextContent(text: 'listed')]);
      }
      return InputRequiredResult(
        inputRequests: {'answer': InputRequest.listRoots(ListRootsRequest())},
      );
    });
  }
}

/// Calls [name] on [protocolVersion]. It defaults to a revision with the
/// requests these tools send, so a capability test reaches the capability
/// check.
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

  test('2026-07-28 checks sampling input capability', () async {
    final refused = await _callTool(
      'test/sample',
      ClientCapabilities(),
      protocolVersion: ProtocolVersion.v2026_07_28,
    );
    final samplingError = refused![Keys.error] as Map<String, Object?>;
    expect(
      samplingError[Keys.code],
      McpErrorCodes.missingRequiredClientCapability,
    );

    final served = await _callTool(
      'test/sample',
      ClientCapabilities(sampling: {}),
      protocolVersion: ProtocolVersion.v2026_07_28,
    );
    expect(served![Keys.error], isNull);
    expect(
      (served[Keys.result] as Map<String, Object?>)[Keys.resultType],
      ResultTypes.inputRequired,
    );
  });

  test('2026-07-28 checks roots input capability', () async {
    final refused = await _callTool(
      'test/roots',
      ClientCapabilities(),
      protocolVersion: ProtocolVersion.v2026_07_28,
    );
    final rootsError = refused![Keys.error] as Map<String, Object?>;
    expect(
      rootsError[Keys.code],
      McpErrorCodes.missingRequiredClientCapability,
    );

    final served = await _callTool(
      'test/roots',
      ClientCapabilities(roots: RootsCapabilities()),
      protocolVersion: ProtocolVersion.v2026_07_28,
    );
    expect(served![Keys.error], isNull);
    expect(
      (served[Keys.result] as Map<String, Object?>)[Keys.resultType],
      ResultTypes.inputRequired,
    );
  });
}
