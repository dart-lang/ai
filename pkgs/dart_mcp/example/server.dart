// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:async/async.dart';
import 'package:dart_mcp/server.dart';
import 'package:stream_channel/stream_channel.dart';

void main() {
  DartMCPServer(
    StreamChannel.withCloseGuarantee(io.stdin, io.stdout)
        .transform(StreamChannelTransformer.fromCodec(utf8))
        .transformStream(const LineSplitter())
        .transformSink(
          StreamSinkTransformer.fromHandlers(
            handleData: (data, sink) {
              sink.add('$data\n');
            },
          ),
        ),
  );
}

/// Our actual MCP server.
class DartMCPServer extends MCPServer with ToolsSupport {
  final ServerCapabilities capabilities = ServerCapabilities(
    prompts: Prompts(),
    tools: Tools(),
  );

  final ServerImplementation implementation = ServerImplementation(
    name: 'example dart server',
    version: '0.1.0',
  );

  DartMCPServer(super.channel) : super.fromStreamChannel();

  @override
  ListToolsResult listTools(ListToolsRequest request) {
    return ListToolsResult(
      tools: [Tool(name: 'hello world', inputSchema: InputSchema())],
    );
  }

  @override
  CallToolResult callTool(CallToolRequest request) {
    switch (request.name) {
      case 'hello world':
        return CallToolResult(content: [TextContent(text: 'hello world!')]);
      default:
        throw ArgumentError.value(request.name, 'name', 'unknown tool');
    }
  }
}
