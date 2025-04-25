// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/server.dart';
import 'package:meta/meta.dart';
import 'package:process/process.dart';
import 'package:stream_channel/stream_channel.dart';

import 'mixins/analyzer.dart';
import 'mixins/dart_cli.dart';
import 'mixins/dtd.dart';
import 'mixins/pub.dart';
import 'utils/process_manager.dart';

/// An MCP server for Dart and Flutter tooling.
final class DartToolingMCPServer extends MCPServer
    with
        LoggingSupport,
        ToolsSupport,
        DartAnalyzerSupport,
        DartCliSupport,
        PubSupport,
        DartToolingDaemonSupport
    implements ProcessManagerSupport {
  DartToolingMCPServer({
    required super.channel,
    @visibleForTesting this.processManager = const LocalProcessManager(),
  }) : super.fromStreamChannel(
         implementation: ServerImplementation(
           name: 'dart and flutter tooling',
           version: '0.1.0-wip',
         ),
         instructions:
             'This server helps to connect Dart and Flutter developers to '
             'their development tools and running applications.',
       );

  static Future<DartToolingMCPServer> connect(
    StreamChannel<String> mcpChannel,
  ) async {
    return DartToolingMCPServer(channel: mcpChannel);
  }

  @override
  final LocalProcessManager processManager;
}
