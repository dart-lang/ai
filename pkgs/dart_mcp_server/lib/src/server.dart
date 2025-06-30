// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:async/async.dart';
import 'package:dart_mcp/server.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:meta/meta.dart';
import 'package:process/process.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:unified_analytics/unified_analytics.dart';

import 'arg_parser.dart';
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

  /// Runs the MCP server given command line arguments and an optional
  /// [Analytics] instance.
  ///
  /// Returns a [Future] that completes with an exit code after the server has
  /// shut down.
  static Future<int> run(List<String> args, {Analytics? analytics}) async {
    final parsedArgs = argParser.parse(args);
    if (parsedArgs.flag(helpFlag)) {
      print(argParser.usage);
      return 0;
    }

    DartMCPServer? server;
    final dartSdkPath =
        parsedArgs.option(dartSdkOption) ?? io.Platform.environment['DART_SDK'];
    final flutterSdkPath =
        parsedArgs.option(flutterSdkOption) ??
        io.Platform.environment['FLUTTER_SDK'];
    final logFilePath = parsedArgs.option(logFileOption);
    final logFileSink =
        logFilePath == null ? null : _createLogSink(io.File(logFilePath));
    runZonedGuarded(
      () {
        server = DartMCPServer(
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
          forceRootsFallback: parsedArgs.flag(forceRootsFallbackFlag),
          sdk: Sdk.find(
            dartSdkPath: dartSdkPath,
            flutterSdkPath: flutterSdkPath,
          ),
          analytics: analytics,
          protocolLogSink: logFileSink,
        )..done.whenComplete(() => logFileSink?.close());
      },
      (e, s) {
        if (server != null) {
          try {
            // Log unhandled errors to the client, if we managed to connect.
            server!.log(LoggingLevel.error, '$e\n$s');
          } catch (_) {}
        } else {
          // Otherwise log to stderr.
          io.stderr
            ..writeln(e)
            ..writeln(s);
        }
      },
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, value) {
          if (server != null) {
            try {
              // Don't allow `print` since this breaks stdio communication, but
              // if we have a server we do log messages to the client.
              server!.log(LoggingLevel.info, value);
            } catch (_) {}
          }
        },
      ),
    );
    if (server == null) {
      return 1;
    } else {
      await server!.done;
      return 0;
    }
  }

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
    FutureOr<CallToolResult> Function(CallToolRequest) impl, {
    bool validateArguments = true,
  }) {
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
      validateArguments: validateArguments,
    );
  }
}

/// Creates a `Sink<String>` for [logFile].
Sink<String> _createLogSink(io.File logFile) {
  logFile.createSync(recursive: true);
  final fileByteSink = logFile.openWrite(
    mode: io.FileMode.write,
    encoding: utf8,
  );
  return fileByteSink.transform(
    StreamSinkTransformer.fromHandlers(
      handleData: (data, innerSink) {
        innerSink.add(utf8.encode(data));
      },
      handleDone: (innerSink) async {
        innerSink.close();
      },
      handleError: (Object e, StackTrace s, _) {
        io.stderr.writeln(
          'Error in writing to log file ${logFile.path}: $e\n$s',
        );
      },
    ),
  );
}
