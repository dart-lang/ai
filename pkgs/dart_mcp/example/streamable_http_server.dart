// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A server reachable over the Streamable HTTP transport from the 2026-07-28
/// revision of the protocol.
///
/// Run it with `dart run example/streamable_http_server.dart`. It prints a
/// `curl` command for the tool it registers, which is how this example is
/// driven. The command asks for progress
/// and the tool reports it, so the answer comes back as an SSE response
/// stream: the report first, then a result containing `Hello, world!`.
library;

import 'dart:io' as io;

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/streamable_http.dart';

void main() async {
  // The one path this server answers on.
  const path = '/mcp';
  final httpServer = await io.HttpServer.bind(
    io.InternetAddress.loopbackIPv4,
    0,
  );
  final endpoint = 'http://${httpServer.address.host}:${httpServer.port}$path';

  httpServer.listen((request) async {
    // The handler reads no path, so the one this server answers on is the
    // host's to choose and to enforce.
    if (request.uri.path != path) {
      request.response
        ..statusCode = io.HttpStatus.notFound
        ..contentLength = 0;
      await request.response.close();
      return;
    }

    // Loopback is not protection on its own, since DNS rebinding reaches it
    // from a remote page. The specification requires a server to answer 403
    // when `Origin` is present and invalid; nothing here is meant to be driven
    // from a page, so no origin is valid. Read the header as a list: `value`
    // throws when a request repeats it, and a caller chooses that.
    if (request.headers['origin'] != null) {
      request.response
        ..statusCode = io.HttpStatus.forbidden
        ..contentLength = 0;
      await request.response.close();
      return;
    }

    // The handler also leaves authentication to the host. This example does
    // not authenticate the caller. A server reachable from anywhere but this
    // machine needs it.

    // Every POST gets its own server: this protocol revision carries the client
    // context on the request instead of an `initialize` handshake, so there is
    // no connection to keep around between requests.
    try {
      await handleStreamableHttpRequest(
        request,
        MCPServerWithGreeting.new,
        // `greet` sends a notification when the request carries a progress
        // token, which the command below does. It goes out on the response
        // stream, and this callback is the host's own copy of it.
        onNotification:
            (notification) => io.stderr.writeln('notification: $notification'),
      );
    } catch (error) {
      // The request already carries the failure. This is the host's copy.
      io.stderr.writeln('request failed: $error');
    }
  });

  print('Listening on $endpoint\n');
  // `Mcp-Method` and `Mcp-Name` mirror the body so that intermediaries can
  // route and inspect the request without parsing it; `Mcp-Name` is only
  // required for the methods that name a target, such as `tools/call`.
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
        "io.modelcontextprotocol/clientInfo": {"name": "curl", "version": "0"},
        "io.modelcontextprotocol/clientCapabilities": {},
        "progressToken": 1
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

  /// A tool that says hello to the name it is given.
  final greetTool = Tool(
    name: 'greet',
    description: 'greets whoever it is given',
    inputSchema: Schema.object(
      properties: {'name': Schema.string(description: 'Who to greet')},
      required: ['name'],
    ),
  );

  /// The implementation of the `greet` tool.
  CallToolResult _greet(CallToolRequest request) {
    // Sending this commits the response to an SSE response stream, and the
    // `curl` command above gets one back.
    if (request.meta?.progressToken case final progressToken?) {
      notifyProgress(
        ProgressNotification(
          progressToken: progressToken,
          progress: 1,
          total: 1,
          message: 'Greeting ${request.arguments!['name']}',
        ),
      );
    }
    return CallToolResult(
      content: [TextContent(text: 'Hello, ${request.arguments!['name']}!')],
    );
  }
}
