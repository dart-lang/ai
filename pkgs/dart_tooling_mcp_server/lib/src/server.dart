// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/server.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:meta/meta.dart';
import 'package:process/process.dart';
import 'package:stream_channel/stream_channel.dart';

import 'mixins/analyzer.dart';
import 'mixins/dash_cli.dart';
import 'mixins/dtd.dart';
import 'mixins/pub.dart';
import 'mixins/pub_dev_search.dart';
import 'mixins/roots_fallback_support.dart';
import 'utils/file_system.dart';
import 'utils/process_manager.dart';

/// An MCP server for Dart and Flutter tooling.
final class DartToolingMCPServer extends MCPServer
    with
        LoggingSupport,
        ToolsSupport,
        ResourcesSupport,
        RootsTrackingSupport,
        RootsFallbackSupport,
        DartAnalyzerSupport,
        DashCliSupport,
        PubSupport,
        PubDevSupport,
        DartToolingDaemonSupport
    implements ProcessManagerSupport, FileSystemSupport {
  DartToolingMCPServer(
    super.channel, {
    @visibleForTesting this.processManager = const LocalProcessManager(),
    @visibleForTesting this.fileSystem = const LocalFileSystem(),
    this.forceRootsFallback = false,
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
    StreamChannel<String> mcpChannel, {
    bool forceRootsFallback = false,
  }) async {
    return DartToolingMCPServer(
      mcpChannel,
      forceRootsFallback: forceRootsFallback,
    );
  }

  @override
  final LocalProcessManager processManager;

  @override
  final FileSystem fileSystem;

  @override
  final bool forceRootsFallback;
}
