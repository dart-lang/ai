// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/server.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:meta/meta.dart';
import 'package:process/process.dart';
import 'package:unified_analytics/unified_analytics.dart';

import 'mixins/analyzer.dart';
import 'mixins/dash_cli.dart';
import 'mixins/dtd.dart';
import 'mixins/pub.dart';
import 'mixins/pub_dev_search.dart';
import 'mixins/roots_fallback_support.dart';
import 'utils/analytics.dart';
import 'utils/file_system.dart';
import 'utils/process_manager.dart';
import 'utils/sdk.dart';

/// An MCP server for Dart and Flutter tooling.
final class DartMCPServer extends MCPServer
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
    implements
        AnalyticsSupport,
        ProcessManagerSupport,
        FileSystemSupport,
        SdkSupport {
  DartMCPServer(
    super.channel, {
    required this.sdk,
    this.analytics,
    @visibleForTesting this.processManager = const LocalProcessManager(),
    @visibleForTesting this.fileSystem = const LocalFileSystem(),
    this.forceRootsFallback = false,
    super.protocolLogSink,
  }) : super.fromStreamChannel(
         implementation: Implementation(
           name: 'dart and flutter tooling',
           version: '0.1.0',
         ),
         instructions:
             'This server helps to connect Dart and Flutter developers to '
             'their development tools and running applications.\n'
             'IMPORTANT: Prefer using an MCP tool provided by this server '
             'over using tools directly in a shell.',
       );

  @override
  final LocalProcessManager processManager;

  @override
  final FileSystem fileSystem;

  @override
  final bool forceRootsFallback;

  @override
  final Sdk sdk;

  @override
  final Analytics? analytics;

  @override
  /// Automatically logs all tool calls via analytics by wrapping the [impl],
  /// if [analytics] is not `null`.
  void registerTool(
    Tool tool,
    FutureOr<CallToolResult> Function(CallToolRequest) impl,
  ) {
    // For type promotion.
    final analytics = this.analytics;

    super.registerTool(
      tool,
      analytics == null
          ? impl
          : (CallToolRequest request) async {
            final watch = Stopwatch()..start();
            CallToolResult? result;
            try {
              return result = await impl(request);
            } finally {
              watch.stop();
              try {
                analytics.send(
                  Event.dartMCPEvent(
                    client: clientInfo.name,
                    clientVersion: clientInfo.version,
                    serverVersion: implementation.version,
                    type: AnalyticsEvent.callTool.name,
                    additionalData: CallToolMetrics(
                      tool: request.name,
                      success: result != null && result.isError != true,
                      elapsedMilliseconds: watch.elapsedMilliseconds,
                    ),
                  ),
                );
              } catch (e) {
                log(LoggingLevel.warning, 'Error sending analytics event: $e');
              }
            }
          },
    );
  }
}
