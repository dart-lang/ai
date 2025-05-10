// ignore_for_file: unused_import

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

  @MCPTool(description: "add two numbers")
  num add(num a, num b) {
    return a + b;
  }
}

void main(List<String> args) {
  final server = MCPDemoServer();
  server.run(args);
}
