// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/server.dart';
import 'package:dtd/dtd.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:vm_service/vm_service_io.dart';

import 'dtd.dart';

/// An MCP server that is connected to the Dart Tooling Daemon (see
/// https://pub.dev/packages/dtd).
class DartToolingMCPServer extends MCPServer with ToolsSupport {
  @override
  final implementation = ServerImplementation(
    name: 'dart tooling daemon',
    version: '0.1.0-wip',
  );

  @override
  final instructions =
      'This server helps to connect Dart and Flutter developers to their '
      'development tools and running applications.';

  /// The tooling daemon we are connected to.
  final DartToolingDaemon dtd;

  DartToolingMCPServer(this.dtd, StreamChannel<String> mcpChannel)
    : super.fromStreamChannel(mcpChannel) {
    _listenForServices();
  }

  static Future<DartToolingMCPServer> connect(
    Uri toolingDaemonUri,
    StreamChannel<String> mcpChannel,
  ) async {
    final dtd = await DartToolingDaemon.connect(toolingDaemonUri);

    return DartToolingMCPServer(dtd, mcpChannel);
  }

  /// Listens to the `Service` stream
  void _listenForServices() {
    dtd.onEvent('Service').listen((e) async {
      switch (e.kind) {
        case 'ServiceRegistered':
          if (e.data['service'] == 'Editor' &&
              e.data['method'] == 'getDebugSessions') {
            registerTool(_screenshotTool, takeScreenshot);
          }
        case 'ServiceUnregistered':
          if (e.data['service'] == 'Editor' &&
              e.data['method'] == 'getDebugSessions') {
            unregisterTool(_screenshotTool.name);
          }
      }
    });
    dtd.streamListen('Service');
  }

  /// Takes a screenshot of the currently running app.
  ///
  /// If more than one debug session is active, then it just uses the first one.
  //
  // TODO: support passing a debug session id when there is more than one debug
  // session.
  Future<CallToolResult> takeScreenshot(CallToolRequest request) async {
    final response = await dtd.getDebugSessions();
    final debugSessions = response.debugSessions;
    if (debugSessions.isEmpty) {
      return CallToolResult(
        content: [
          TextContent(text: 'No active debug session to take a screenshot'),
        ],
        isError: true,
      );
    }

    // TODO: Consider holding on to this connection.
    final vmService = await vmServiceConnectUri(
      debugSessions.first.vmServiceUri,
    );

    try {
      final vm = await vmService.getVM();
      final result = await vmService.callServiceExtension(
        '_flutter.screenshot',
        isolateId: vm.isolates!.first.id,
      );
      if (result.json?['type'] == 'Screenshot' &&
          result.json?['screenshot'] is String) {
        return CallToolResult(
          content: [
            ImageContent(
              data: result.json!['screenshot'] as String,
              mimeType: 'image/png',
            ),
          ],
        );
      } else {
        return CallToolResult(
          isError: true,
          content: [
            TextContent(
              text:
                  'Unknown error or bad response taking screenshot:\n'
                  '${result.json}',
            ),
          ],
        );
      }
    } finally {
      unawaited(vmService.dispose());
    }
  }
}

final _screenshotTool = Tool(
  name: 'take_screenshot',
  description:
      'Takes a screenshot of the flutter application in its '
      'current state',
  inputSchema: InputSchema(),
);
