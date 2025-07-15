// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// A client that connects to a server and exercises the tools API.
import 'dart:async';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/stdio.dart';

void main() async {
  // Create a client, which is the top level object that manages all
  // server connections.
  final client = MCPClient(
    Implementation(name: 'example dart client', version: '0.1.0'),
  );
  print('connecting to server');

  // Start the server as a separate process.
  final process = await Process.start('dart', [
    'run',
    'example/tools_server.dart',
  ]);
  // Connect the client to the server.
  final server = client.connectServer(
    stdioChannel(input: process.stdout, output: process.stdin),
  );
  // When the server connection is closed, kill the process.
  unawaited(server.done.then((_) => process.kill()));
  print('server started');

  // Initialize the server and let it know our capabilities.
  print('initializing server');
  final initializeResult = await server.initialize(
    InitializeRequest(
      protocolVersion: ProtocolVersion.latestSupported,
      capabilities: client.capabilities,
      clientInfo: client.implementation,
    ),
  );
  print('initialized: $initializeResult');

  // Ensure the server supports the tools capability.
  if (initializeResult.capabilities.tools == null) {
    await server.shutdown();
    throw StateError('Server doesn\'t support tools!');
  }

  // Notify the server that we are initialized.
  server.notifyInitialized();
  print('sent initialized notification');

  // List all the available tools from the server.
  print('Listing tools from server');
  final toolsResult = await server.listTools(ListToolsRequest());
  for (final tool in toolsResult.tools) {
    print('Found Tool: ${tool.name}');
    // Normally, you would expose these tools to an LLM to call them as it
    // sees fit. To keep this example simple and not require any API keys, we
    // just manually call the `concat` tool.
    if (tool.name == 'concat') {
      print('Calling `${tool.name}` tool');
      // Should return "abcd".
      final result = await server.callTool(
        CallToolRequest(
          name: tool.name,
          arguments: {
            'parts': ['a', 'b', 'c', 'd'],
          },
        ),
      );
      if (result.isError == true) {
        throw StateError('Tool call failed: ${result.content}');
      } else {
        print('Tool call succeeded: ${result.content}');
      }
    } else {
      throw ArgumentError('Unexpected tool ${tool.name}');
    }
  }

  // Shutdown the client, which will also shutdown the server connection.
  await client.shutdown();
}
