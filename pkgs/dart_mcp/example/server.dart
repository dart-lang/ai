// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io' as io;

import 'package:dart_mcp/server.dart';
import 'package:stream_channel/stream_channel.dart';
// import 'package:json_rpc_2/json_rpc_2.dart';

void main() {
  DartMCPServer(
    StreamChannel(io.stdin, io.stdout)
        .transform(StreamChannelTransformer.fromCodec(utf8))
        .transformStream(const LineSplitter()),
  );
}

/// Our actual MCP server.
class DartMCPServer extends MCPServer with ToolsSupport {
  final ServerCapabilities capabilities = ServerCapabilities(
    prompts: Prompts(),
    tools: Tools(),
  );
  final ServerImplementation implementation = ServerImplementation(
    name: 'dart_mcp',
    version: '0.1.0',
  );

  DartMCPServer(super.channel) : super.fromStreamChannel();

  @override
  ListToolsResult listTools(ListToolsRequest request) {
    return ListToolsResult(
      tools: [Tool(name: 'hello world', inputSchema: InputSchema())],
    );
  }
}
