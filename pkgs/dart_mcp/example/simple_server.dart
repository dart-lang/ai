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
base class DartMCPServer extends MCPServer with ToolsSupport {
  DartMCPServer(super.channel)
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'example dart server',
          version: '0.1.0',
        ),
        instructions: 'A basic tool that can respond with "hello world!"',
      );

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    registerTool(
      Tool(name: 'hello_world', inputSchema: ObjectSchema()),
      (_) => CallToolResult(content: [TextContent(text: 'hello world!')]),
    );
    return super.initialize(request);
  }
}
