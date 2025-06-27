// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:dart_mcp/client.dart';

void main() async {
  final client = MCPClient(
    Implementation(name: 'example dart client', version: '0.1.0'),
  );
  print('connecting to server');

  final process = await Process.start('dart', [
    'run',
    'example/simple_server.dart',
  ]);
  final server = client.connectStdioServer(
    process.stdin,
    process.stdout,
    onDone: process.kill,
  );
  print('server started');

  print('initializing server');
  final initializeResult = await server.initialize(
    InitializeRequest(
      protocolVersion: ProtocolVersion.latestSupported,
      capabilities: client.capabilities,
      clientInfo: client.implementation,
    ),
  );
  print('initialized: $initializeResult');
  if (!initializeResult.protocolVersion!.isSupported) {
    throw StateError(
      'Protocol version mismatch, expected a version between '
      '${ProtocolVersion.oldestSupported} and '
      '${ProtocolVersion.latestSupported}, but received '
      '${initializeResult.protocolVersion}',
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
    if (tool.name == 'hello_world') {
      print('Calling `hello_world` tool');
      final result = await server.callTool(
        CallToolRequest(name: 'hello_world'),
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
