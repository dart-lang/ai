// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io' as io;

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/stdio.dart';

void main() {
  MCPServerWithTools(stdioChannel(input: io.stdin, output: io.stdout));
}

/// Our actual MCP server.
base class MCPServerWithTools extends MCPServer with ToolsSupport {
  MCPServerWithTools(super.channel)
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'An example dart server with tools support',
          version: '0.1.0',
        ),
        instructions: 'Just list and call the tools :D',
      );

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    registerTool(concatTool, _concat);
    return super.initialize(request);
  }

  final concatTool = Tool(
    name: 'concat',
    description: 'concatenates many string parts into one string',
    inputSchema: Schema.object(
      properties: {
        'parts': Schema.list(
          description: 'The parts to concatenate together',
          items: Schema.string(),
        ),
      },
      required: ['parts'],
    ),
  );
  FutureOr<CallToolResult> _concat(CallToolRequest request) => CallToolResult(
    content: [
      TextContent(text: (request.arguments!['parts'] as List<String>).join('')),
    ],
  );
}
