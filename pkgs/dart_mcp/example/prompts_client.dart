// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/stdio.dart';

void main() async {
  final client = MCPClient(
    Implementation(name: 'example dart client', version: '0.1.0'),
  );
  print('connecting to server');

  final process = await Process.start('dart', [
    'run',
    'example/prompts_server.dart',
  ]);
  final server = client.connectServer(
    stdioChannel(input: process.stdout, output: process.stdin),
  );
  unawaited(server.done.then((_) => process.kill()));
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

  if (initializeResult.capabilities.prompts == null) {
    await server.shutdown();
    throw StateError('Server doesn\'t support prompts!');
  }

  server.notifyInitialized();
  print('sent initialized notification');

  print('Listing prompts from server');
  final promptsResult = await server.listPrompts(ListPromptsRequest());
  for (final prompt in promptsResult.prompts) {
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

  await client.shutdown();
}
