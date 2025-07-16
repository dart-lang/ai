// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A client that connects to a server and uses the [SamplingSupport] mixin to
/// responds to sampling requests.
library;

import 'dart:async';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:stream_channel/stream_channel.dart';

void main() async {
  // Create a client, which is the top level object that manages all
  // server connections.
  final client = MCPClientWithSamplingSupport(
    Implementation(name: 'example dart client', version: '0.1.0'),
  );
  print('connecting to server');

  // Start the server as a separate process.
  final process = await Process.start('dart', [
    'run',
    'example/sampling_server.dart',
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

  // Notify the server that we are initialized.
  server.notifyInitialized();
  print('sent initialized notification');

  print('waiting for the server to send sampling requests');
}

/// A client which implements sampling support by mixing in [SamplingSupport].
///
/// This implementation just echos back the message to confirm it was received.
final class MCPClientWithSamplingSupport extends MCPClient
    with SamplingSupport {
  MCPClientWithSamplingSupport(super.implementation);

  @override
  /// To handle sampling requests, you must implement this function.
  FutureOr<CreateMessageResult> handleCreateMessage(
    CreateMessageRequest request,
    Implementation serverInfo,
  ) {
    // Simply echo back the message to avoid the need for API keys and actual
    // model interactions.
    //
    // Note that in a real client, you should also ask the user to approve the
    // elicitation request.
    print('Received sampling request: $request');
    return CreateMessageResult(
      role: Role.assistant,
      content: Content.text(
        text:
            'You asked '
            '"${(request.messages.single.content as TextContent).text}"',
      ),
      model: 'Echo bot',
    );
  }

  /// Whenever connecting to a server, we also listen for log messages.
  ///
  /// The server will log the responses it gets to sampling messages.
  @override
  ServerConnection connectServer(
    StreamChannel<String> channel, {
    Sink<String>? protocolLogSink,
  }) {
    final connection = super.connectServer(
      channel,
      protocolLogSink: protocolLogSink,
    );
    // Whenever a log message is received, print it to the console.
    connection.onLog.listen((message) {
      print('[${message.level}]: ${message.data}');
    });
    return connection;
  }
}
