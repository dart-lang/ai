// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A client that connects over Streamable HTTP to
/// `streamable_http_server.dart`.
///
/// Pass the printed URL to discover the server, list tools, call `greet`,
/// and print progress.
library;

import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/streamable_http.dart';

void main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln(
      'Usage: dart run example/streamable_http_client.dart <url>\n'
      'Pass the URL printed by example/streamable_http_server.dart.',
    );
    exitCode = 64;
    return;
  }

  // Create a client, which is the top level object that manages all
  // server connections.
  final client = MCPClient(
    Implementation(name: 'example dart client', version: '0.1.0'),
  );
  // The server example prints this URL after it binds.
  final uri = Uri.parse(args.single);
  print('connecting to server at $uri');

  // Streamable HTTP on 2026-07-28 does not send initialize.
  final protocolVersion = ProtocolVersion.v2026_07_28;
  final server = client.connectServer(
    streamableHttpClientChannel(
      uri,
      protocolVersion: protocolVersion,
      clientCapabilities: client.capabilities,
      clientInfo: client.implementation,
    ),
  );
  // This revision settles the version on the transport, not through
  // initialize.
  server.protocolVersion = protocolVersion;

  try {
    print('discovering server');
    final discoverResult = await server.discover(
      protocolVersion: protocolVersion,
      capabilities: client.capabilities,
      clientInfo: client.implementation,
    );
    print('discover: $discoverResult');

    if (discoverResult.capabilities.tools == null) {
      throw StateError('Server doesn\'t support tools!');
    }

    print('Listing tools from server');
    final toolsResult = await server.listTools(ListToolsRequest());
    for (final tool in toolsResult.tools) {
      print('Found Tool: ${tool.name}');
      if (tool.name == 'greet') {
        print('Calling `${tool.name}` tool');
        final request = CallToolRequest(
          name: tool.name,
          arguments: {'name': 'world'},
          meta: MetaWithProgressToken(progressToken: ProgressToken(1)),
        );
        // Listen before awaiting the response.
        server.onProgress(request).listen((progress) {
          print(
            'Progress: ${progress.progress}/${progress.total}: '
            '${progress.message}',
          );
        });
        final result = await server.callTool(request);
        if (result.isError == true) {
          throw StateError('Tool call failed: ${result.content}');
        } else {
          print('Tool call succeeded: ${result.content}');
        }
      } else {
        throw ArgumentError('Unexpected tool ${tool.name}');
      }
    }
  } finally {
    await client.shutdown();
  }
}
