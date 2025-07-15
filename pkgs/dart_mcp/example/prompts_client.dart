// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A client that interacts with a server that provides prompts.
library;

import 'dart:async';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/stdio.dart';

void main() async {
  // Create the client, which is the top level object that manages all
  // server connections.
  final client = MCPClient(
    Implementation(name: 'example dart client', version: '0.1.0'),
  );
  print('connecting to server');

  // Start the server as a separate process.
  final process = await Process.start('dart', [
    'run',
    'example/prompts_server.dart',
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

  // Ensure the server supports the prompts capability.
  if (initializeResult.capabilities.prompts == null) {
    await server.shutdown();
    throw StateError('Server doesn\'t support prompts!');
  }

  // Notify the server that we are initialized.
  server.notifyInitialized();
  print('sent initialized notification');

  // List all the available prompts from the server.
  print('Listing prompts from server');
  final promptsResult = await server.listPrompts(ListPromptsRequest());
  for (final prompt in promptsResult.prompts) {
    // For each prompt, get the full prompt text, filling in any arguments.
    final promptResult = await server.getPrompt(
      GetPromptRequest(
        name: prompt.name,
        arguments: {
          for (var arg in prompt.arguments ?? <PromptArgument>[])
            arg.name: switch (arg.name) {
              'tags' => 'myTag myOtherTag',
              'platforms' => 'vm,chrome',
              _ => throw ArgumentError('Unrecognized argument ${arg.name}'),
            },
        },
      ),
    );
    final promptText = promptResult.messages
        .map((m) => (m.content as TextContent).text)
        .join('');
    print('Found prompt `${prompt.name}`: "$promptText"');
  }

  // Shutdown the client, which will also shutdown the server connection.
  await client.shutdown();
}
