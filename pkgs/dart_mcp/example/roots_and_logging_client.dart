// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:stream_channel/stream_channel.dart';

void main() async {
  final client = MCPClientWithRoots(
    Implementation(name: 'example dart client', version: '0.1.0'),
  );
  print('connecting to server');

  final process = await Process.start('dart', [
    'run',
    'example/roots_and_logging_server.dart',
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

  if (initializeResult.capabilities.logging == null) {
    await server.shutdown();
    throw StateError('Server doesn\'t support logging!');
  }

  server.notifyInitialized();
  print('sent initialized notification');

  await Future<void>.delayed(const Duration(seconds: 1));
  client.addRoot(Root(uri: 'new_root://some_path', name: 'A new root'));

  // Give the logs a chance to propagate.
  await Future<void>.delayed(const Duration(seconds: 1));
  await client.shutdown();
}

final class MCPClientWithRoots extends MCPClient with RootsSupport {
  MCPClientWithRoots(super.implementation) {
    addRoot(Root(uri: Directory.current.path, name: 'Working dir'));
  }

  @override
  ServerConnection connectServer(
    StreamChannel<String> channel, {
    Sink<String>? protocolLogSink,
  }) {
    final connection = super.connectServer(
      channel,
      protocolLogSink: protocolLogSink,
    );
    connection.onLog.listen((message) {
      print('[${message.level}]: ${message.data}');
    });
    return connection;
  }
}
