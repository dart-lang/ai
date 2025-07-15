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
    'example/resources_server.dart',
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

  if (initializeResult.capabilities.resources == null) {
    await server.shutdown();
    throw StateError('Server doesn\'t support resources!');
  }

  server.notifyInitialized();
  print('sent initialized notification');

  print('Listing resources from server');
  final resourcesResult = await server.listResources(ListResourcesRequest());
  for (final resource in resourcesResult.resources) {
    final content = (await server.readResource(
      ReadResourceRequest(uri: resource.uri),
    )).contents.map((part) => (part as TextResourceContents).text).join('');
    print(
      'Found resource: ${resource.name} with uri ${resource.uri} and contents: '
      '"$content"',
    );
  }

  print('Listing resource templates from server');
  final templatesResult = await server.listResourceTemplates(
    ListResourceTemplatesRequest(),
  );
  for (final template in templatesResult.resourceTemplates) {
    print('Found resource template `${template.uriTemplate}`');
    for (var path in ['zip', 'zap']) {
      final uri = template.uriTemplate.replaceFirst(RegExp('{.*}'), path);
      final contents = (await server.readResource(
        ReadResourceRequest(uri: uri),
      )).contents.map((part) => (part as TextResourceContents).text).join('');
      print('Read resource `$uri`: "$contents"');
    }
  }

  await client.shutdown();
}
