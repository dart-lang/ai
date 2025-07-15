// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// A client that connects to a server and exercises the roots and logging APIs.
import 'dart:async';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:stream_channel/stream_channel.dart';

void main() async {
  // Create a client, which is the top level object that manages all
  // server connections.
  final client = MCPClientWithRoots(
    Implementation(name: 'example dart client', version: '0.1.0'),
  );
  print('connecting to server');

  // Start the server as a separate process.
  final process = await Process.start('dart', [
    'run',
    'example/roots_and_logging_server.dart',
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

  // Ensure the server supports the logging capability.
  if (initializeResult.capabilities.logging == null) {
    await server.shutdown();
    throw StateError('Server doesn\'t support logging!');
  }

  // Notify the server that we are initialized.
  server.notifyInitialized();
  print('sent initialized notification');

  // Wait a second and then add a new root, the server is going to send a log
  // back confirming that it got the notification that the roots changed.
  await Future<void>.delayed(const Duration(seconds: 1));
  client.addRoot(Root(uri: 'new_root://some_path', name: 'A new root'));

  // Give the logs a chance to propagate.
  await Future<void>.delayed(const Duration(seconds: 1));
  // Shutdown the client, which will also shutdown the server connection.
  await client.shutdown();
}

/// A custom client that uses the [RootsSupport] mixin.
///
/// This allows the client to manage a set of roots and notify servers of
/// changes to them.
final class MCPClientWithRoots extends MCPClient with RootsSupport {
  MCPClientWithRoots(super.implementation) {
    // Add an initial root for the current working directory.
    addRoot(Root(uri: Directory.current.path, name: 'Working dir'));
  }

  /// Whenever connecting to a server, we also listen for log messages.
  ///
  /// The server we connect to will log the roots that it sees, both on startup
  /// and any time they change.
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
