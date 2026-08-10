// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/src/utils/constants.dart';
import 'package:test/test.dart';

final class _ElicitingServer extends MCPServer
    with LoggingSupport, ToolsSupport, ElicitationRequestSupport {
  _ElicitingServer(super.channel)
    : super.fromStreamChannel(
        implementation: Implementation(name: 'test', version: '0.1.0'),
      ) {
    registerTool(Tool(name: 'test/ask', inputSchema: ObjectSchema()), (
      _,
    ) async {
      await elicit(
        ElicitRequest(message: 'need input', requestedSchema: ObjectSchema()),
      );
      return CallToolResult(content: [TextContent(text: 'asked')]);
    });
  }
}

void main() {
  test('a tool which elicits fails with the missing capability code', () async {
    final result = await handleRequestScopedMessage(
      {
        Keys.jsonrpc: '2.0',
        Keys.id: 1,
        Keys.method: CallToolRequest.methodName,
        Keys.params: {Keys.name: 'test/ask'},
      },
      MCPServerInitialization(
        protocolVersion: ProtocolVersion.v2026_07_28,
        clientCapabilities: ClientCapabilities(),
      ),
      _ElicitingServer.new,
    );

    final error = result![Keys.error] as Map<String, Object?>;
    expect(error[Keys.code], McpErrorCodes.missingRequiredClientCapability);
    // In memory the data skips the JSON round trip, so it is an untyped map.
    final data = error[Keys.data] as Map;
    expect(data[Keys.requiredCapabilities], {
      Keys.elicitation: <String, Object?>{},
    });
    expect(result[Keys.result], isNull);
  });
}
