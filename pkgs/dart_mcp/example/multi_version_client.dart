// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A client answering the elicitation that the `greet` tool of
/// `example/multi_version_server.dart` needs.
///
/// Run `dart run example/multi_version_client.dart`. It spawns the server over
/// stdio, where the negotiated revision is older than 2026-07-28 and the
/// tool's [InputRequiredResult] arrives as an `elicitation/create` request.
library;

import 'dart:async';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/stdio.dart';

void main() async {
  final client = GreetingClient(
    Implementation(name: 'example dart client', version: '0.1.0'),
  );

  // The server serves stdio when it gets no arguments.
  final process = await Process.start('dart', [
    'run',
    'example/multi_version_server.dart',
  ]);
  final server = client.connectServer(
    stdioChannel(input: process.stdout, output: process.stdin),
  );
  // When the server connection is closed, kill the process.
  unawaited(server.done.then((_) => process.kill()));

  final initializeResult = await server.initialize(
    InitializeRequest(
      protocolVersion: ProtocolVersion.latestSupported,
      capabilities: client.capabilities,
      clientInfo: client.implementation,
    ),
  );
  print('initialized on ${initializeResult.protocolVersion?.versionString}');
  server.notifyInitialized();

  // The tool takes no arguments. It asks for the name it greets instead.
  final result = await server.callTool(CallToolRequest(name: 'greet'));
  for (final content in result.content) {
    if (content.isText) print((content as TextContent).text);
  }

  await client.shutdown();
}

/// A client which accepts every form elicitation with the same name.
final class GreetingClient extends MCPClient with ElicitationFormSupport {
  GreetingClient(super.implementation);

  @override
  FutureOr<ElicitResult> handleElicitation(
    ElicitRequest request,
    ServerConnection connection,
  ) {
    print('server asks: ${request.message}');
    return ElicitResult(
      action: ElicitationAction.accept,
      content: {'name': 'world'},
    );
  }
}
