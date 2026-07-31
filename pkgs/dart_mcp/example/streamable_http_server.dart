// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A server reachable over the Streamable HTTP transport from the 2026-07-28
/// revision of the protocol.
///
/// Run it with `dart run example/streamable_http_server.dart`. It prints a
/// `curl` command for the tool it registers; the transport has no client in
/// this package yet, so that is how to drive it.
library;

import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/streamable_http.dart';

void main() async {
  final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 8080);

  // Every POST gets its own server: this protocol revision carries the client
  // context on the request instead of an `initialize` handshake, so there is
  // no connection to keep around between requests.
  httpServer.listen(
    (request) => handleStreamableHttpRequest(
      request,
      MCPServerWithGreeting.new,
      // A JSON response body cannot carry notifications, so anything the
      // server logs while handling the request is dropped without this.
      onNotification:
          (notification) => stderr.writeln('notification: $notification'),
    ),
  );

  final endpoint = 'http://${httpServer.address.host}:${httpServer.port}/mcp';
  print('Listening on $endpoint\n');
  print('''
curl -sS $endpoint \\
  -H 'Content-Type: application/json' \\
  -H 'Accept: application/json, text/event-stream' \\
  -H 'MCP-Protocol-Version: 2026-07-28' \\
  -H 'Mcp-Method: tools/call' \\
  -H 'Mcp-Name: greet' \\
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call",
    "params": {
      "name": "greet",
      "arguments": {"name": "world"},
      "_meta": {
        "io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": {}
      }
    }
  }'
''');
}

/// A server with one tool, built fresh for each request.
base class MCPServerWithGreeting extends MCPServer with ToolsSupport {
  MCPServerWithGreeting(super.channel)
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'An example dart server on Streamable HTTP',
          version: '0.1.0',
        ),
      ) {
    registerTool(greetTool, _greet);
  }

  final greetTool = Tool(
    name: 'greet',
    description: 'greets whoever it is given',
    inputSchema: Schema.object(
      properties: {'name': Schema.string(description: 'Who to greet')},
      required: ['name'],
    ),
  );

  CallToolResult _greet(CallToolRequest request) => CallToolResult(
    content: [TextContent(text: 'Hello, ${request.arguments!['name']}!')],
  );
}
