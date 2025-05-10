// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:mcp_annotations/mcp_annotations.dart';
import 'dart:convert';
import 'package:stream_channel/stream_channel.dart';
import 'package:async/async.dart';
import 'package:dart_mcp/server.dart';
import 'dart:io';
import 'dart:async';

part 'main.mcp.g.dart';

@MCPServerApp(name: 'demo_server', version: '0.1.0')
class MCPDemoServer {
  const MCPDemoServer();

  @MCPTool(description: 'Adds two numbers.')
  num add(num a, num b) => a + b;

  @MCPTool(
    description: 'Returns the length of a string.',
    parameters: [
      MCPParameter(
        name: 'text',
        description: 'The string to get the length of.',
      ),
    ],
  )
  int strlen(String text) {
    return text.length;
  }
}

void main(List<String> args) {
  final server = MCPDemoServer();
  server.run(args);
}
