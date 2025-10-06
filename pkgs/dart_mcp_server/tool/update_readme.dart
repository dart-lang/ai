// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/stdio.dart';

void main(List<String> args) async {
  print('Getting registered tools...');

  final tools = await _retrieveRegisteredTools();
  tools.sortBy((tool) => tool.name);

  final buf = StringBuffer('''
| Tool Name | Title | Description |
| --- | --- | --- |
''');
  for (final tool in tools) {
    buf.writeln(
      '| `${tool.name}` | ${tool.displayName} | ${tool.description} |',
    );
  }

  final readmeFile = File('README.md');
  final updated = _insertBetween(
    readmeFile.readAsStringSync(),
    buf.toString(),
    '<!-- generated -->',
  );
  readmeFile.writeAsStringSync(updated);

  print('Wrote update tool list to ${readmeFile.path}.');
}

String _insertBetween(String original, String insertion, String marker) {
  final startIndex = original.indexOf(marker) + marker.length;
  final endIndex = original.lastIndexOf(marker);

  return '${original.substring(0, startIndex)}\n\n'
      '$insertion\n${original.substring(endIndex)}';
}

Future<List<Tool>> _retrieveRegisteredTools() async {
  final client = MCPClient(
    Implementation(name: 'list tools client', version: '1.0.0'),
  );
  final process = await Process.start('dart', ['run', 'bin/main.dart']);
  final server = client.connectServer(
    stdioChannel(input: process.stdout, output: process.stdin),
  );
  unawaited(server.done.then((_) => process.kill()));

  await server.initialize(
    InitializeRequest(
      protocolVersion: ProtocolVersion.latestSupported,
      capabilities: client.capabilities,
      clientInfo: client.implementation,
    ),
  );
  server.notifyInitialized(InitializedNotification());

  final toolsResult = await server.listTools(ListToolsRequest());
  await client.shutdown();
  return toolsResult.tools;
}

extension on Tool {
  String get displayName => toolAnnotations?.title ?? '';
}
