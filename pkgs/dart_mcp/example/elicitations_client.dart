// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A client that connects to a server and supports elicitation requests.
library;

import 'dart:async';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:stream_channel/stream_channel.dart';

void main() async {
  // Create a client, which is the top level object that manages all
  // server connections.
  final client = TestMCPClientWithElicitationSupport(
    Implementation(name: 'example dart client', version: '0.1.0'),
  );
  print('connecting to server');

  // Start the server as a separate process.
  final process = await Process.start('dart', [
    'run',
    'example/elicitations_server.dart',
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

  print('waiting for elicitation requests');
}

/// A client that supports elicitation requests using the [ElicitationSupport]
/// mixin.
///
/// Prompts the user for values on stdin.
final class TestMCPClientWithElicitationSupport extends MCPClient
    with ElicitationSupport {
  TestMCPClientWithElicitationSupport(super.implementation);

  @override
  /// Handle the actual elicitation from the server by reading from stdin.
  FutureOr<ElicitResult> handleElicitation(ElicitRequest request) {
    // Ask the user if they are willing to provide the information first.
    print('''
Elicitation received from server: ${request.message}

Do you want to accept (a), reject (r), or cancel (c) the elicitation?
''');
    final answer = stdin.readLineSync();
    final action = switch (answer) {
      'a' => ElicitationAction.accept,
      'r' => ElicitationAction.reject,
      'c' => ElicitationAction.cancel,
      _ => throw ArgumentError('Invalid answer: $answer'),
    };

    // If they don't accept it, just return the reason.
    if (action != ElicitationAction.accept) {
      return ElicitResult(action: action);
    }

    // User has accepted the elicitation, prompt them for each value.
    final arguments = <String, Object?>{};
    for (final property in request.requestedSchema.properties!.entries) {
      final name = property.key;
      final type = property.value.type;
      final allowedValues =
          type == JsonType.enumeration
              ? ' (${(property.value as EnumSchema).values.join(', ')})'
              : '';
      stdout.write('$name$allowedValues: ');
      final value = stdin.readLineSync()!;
      arguments[name] = switch (type) {
        JsonType.string || JsonType.enumeration => value,
        JsonType.num => num.parse(value),
        JsonType.int => int.parse(value),
        JsonType.bool => bool.parse(value),
        JsonType.object ||
        JsonType.list ||
        JsonType.nil ||
        null => throw StateError('Unsupported field type $type'),
      };
    }
    return ElicitResult(action: ElicitationAction.accept, content: arguments);
  }

  /// Whenever connecting to a server, we also listen for log messages.
  ///
  /// The server we connect to will log the elicitation responses it receives.
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
