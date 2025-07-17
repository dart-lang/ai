// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// A client that connects to a server and exercises the resources API.
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
    'example/resources_server.dart',
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

  // Ensure the server supports the resources capability.
  if (initializeResult.capabilities.resources == null) {
    await server.shutdown();
    throw StateError('Server doesn\'t support resources!');
  }

  // Notify the server that we are initialized.
  server.notifyInitialized();
  print('sent initialized notification');

  // List all the available resources from the server.
  print('Listing resources from server');
  final resourcesResult = await server.listResources(ListResourcesRequest());
  for (final resource in resourcesResult.resources) {
    // For each resource, read its content.
    final content = (await server.readResource(
      ReadResourceRequest(uri: resource.uri),
    )).contents.map((part) => (part as TextResourceContents).text).join('');
    print(
      'Found resource: ${resource.name} with uri ${resource.uri} and contents: '
      '"$content"',
    );
  }

  // List all the available resource templates from the server.
  print('Listing resource templates from server');
  final templatesResult = await server.listResourceTemplates(
    ListResourceTemplatesRequest(),
  );
  for (final template in templatesResult.resourceTemplates) {
    print('Found resource template `${template.uriTemplate}`');
    // For each template, fill in the path variable and read the resource.
    for (var path in ['zip', 'zap']) {
      final uri = template.uriTemplate.replaceFirst(RegExp('{.*}'), path);
      final contents = (await server.readResource(
        ReadResourceRequest(uri: uri),
      )).contents.map((part) => (part as TextResourceContents).text).join('');
      print('Read resource `$uri`: "$contents"');
    }
  }

  // Shutdown the client, which will also shutdown the server connection.
  await client.shutdown();
}
