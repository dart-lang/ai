// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_mcp/client.dart';

void main() async {
  final client = MCPClient(
    ClientImplementation(name: 'example dart client', version: '0.1.0'),
  );
  print('connecting to server');
  final server = await client.connectStdioServer('dart', [
    'run',
    'example/server.dart',
  ]);
  print('server started');

  print('initializing server');
  var initializeResult = await server.initialize(
    InitializeRequest(
      protocolVersion: protocolVersion,
      capabilities: client.capabilities,
      clientInfo: client.implementation,
    ),
  );
  print('initialized: $initializeResult');
  if (initializeResult.protocolVersion != protocolVersion) {
    throw StateError(
      'Protocol version mismatch, expected $protocolVersion, '
      'got ${initializeResult.protocolVersion}',
    );
  }

  if (initializeResult.capabilities.tools == null) {
    await server.shutdown();
    throw StateError('Server doesn\'t support tools!');
  }

  server.notifyInitialized(InitializedNotification());
  print('sent initialized notification');

  print('Listing tools from server');
  final toolsResult = await server.listTools(ListToolsRequest());
  for (final tool in toolsResult.tools) {
    print('Found Tool: ${tool.name}');
    if (tool.name == 'hello world') {
      print('Calling `hello world` tool');
      final result = await server.callTool(
        CallToolRequest(name: 'hello world'),
      );
      if (result.isError == true) {
        throw StateError('Tool call failed: ${result.content}');
      } else {
        print('Tool call succeeded: ${result.content}');
      }
    }
  }

  await client.shutdown();
}
