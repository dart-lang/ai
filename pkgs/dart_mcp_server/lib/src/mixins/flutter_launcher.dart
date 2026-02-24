// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A mixin that provides tools for launching and managing Flutter applications.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dart_mcp/server.dart';
import 'package:meta/meta.dart';

import '../features_configuration.dart';
import '../utils/analytics.dart';
import '../utils/names.dart';
import '../utils/process_manager.dart';
import '../utils/sdk.dart';

class _RunningApp {
  final Process process;
  final List<String> logs = [];
  String? dtdUri;

  _RunningApp(this.process);
}

/// A mixin that provides tools for launching and managing Flutter applications.
///
/// This mixin registers tools for launching, stopping, and listing Flutter
/// applications, as well as listing available devices and retrieving
/// application logs. It manages the lifecycle of Flutter processes that it
/// launches.
base mixin FlutterLauncherSupport
    on ToolsSupport, LoggingSupport, RootsTrackingSupport
    implements ProcessManagerSupport, SdkSupport {
  final Map<int, _RunningApp> _runningApps = {};
  static const Set<String> _managedFlutterRunFlags = {
    '--print-dtd',
    '--machine',
    '--device-id',
    '--target',
    '-d',
    '-t',
  };

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    registerTool(launchAppTool, _launchApp);
    registerTool(stopAppTool, _stopApp);
    registerTool(listDevicesTool, _listDevices);
    registerTool(getAppLogsTool, _getAppLogs);
    registerTool(listRunningAppsTool, _listRunningApps);
    return super.initialize(request);
  }

  @visibleForTesting
  static final List<Tool> allTools = [
    launchAppTool,
    stopAppTool,
    listDevicesTool,
    getAppLogsTool,
    listRunningAppsTool,
  ];

  /// A tool to launch a Flutter application.
  static final launchAppTool = Tool(
    name: ToolNames.launchApp.name,
    description: 'Launches a Flutter application and returns its DTD URI.',
    inputSchema: Schema.object(
      properties: {
        'root': Schema.string(
          description: 'The root directory of the Flutter project.',
        ),
        'target': Schema.string(
          description:
              'The main entry point file of the application. Defaults to "lib/main.dart".',
        ),
        'device': Schema.string(
          description:
              'The device ID to launch the application on. To get a list of '
              'available devices to present as choices, use the '
              'list_devices tool.',
        ),
        'args': Schema.list(
          items: Schema.string(),
          description:
              'Additional arguments to pass to the `flutter run` command. '
              'For example: ["--flavor", "dev", "--dart-define-from-file", '
              '"env.json"]. Do not include '
              '${_managedFlutterRunFlags.join(', ')} '
              'as these are managed automatically.',
        ),
        'timeout': Schema.int(
          description: 'Timeout in milliseconds, defaults to 90000.',
        ),
      },
      required: ['root', 'device'],
      additionalProperties: false,
    ),
    outputSchema: Schema.object(
      properties: {
        ParameterNames.dtdUri: Schema.string(
          description: 'The DTD URI of the launched Flutter application.',
        ),
        ParameterNames.pid: Schema.int(
          description: 'The process ID of the launched Flutter application.',
        ),
      },
      required: [ParameterNames.dtdUri, ParameterNames.pid],
    ),
  )..categories = [FeatureCategory.flutter];

  Future<CallToolResult> _launchApp(CallToolRequest request) async {
    final root = request.arguments!['root'] as String;
    final target = request.arguments!['target'] as String?;
    final device = request.arguments!['device'] as String;
    final args =
        (request.arguments!['args'] as List<Object?>?)?.cast<String>() ??
        <String>[];
    final blockedArgs = args
        .where(
          (arg) => _managedFlutterRunFlags.any(
            (flag) => arg == flag || arg.startsWith('$flag='),
          ),
        )
        .toList();
    if (blockedArgs.isNotEmpty) {
      log(
        LoggingLevel.warning,
        'launch_app called with managed flutter run flags in args: '
        '${blockedArgs.join(', ')}',
      );
      return CallToolResult(
        isError: true,
        content: [
          TextContent(
            text:
                'The `args` parameter contains managed flutter run options: '
                '${blockedArgs.map((arg) => '`$arg`').join(', ')}. Remove '
                'these from `args`; use the `device` and `target` parameters '
                'instead.',
          ),
        ],
      )..failureReason = CallToolFailureReason.argumentError;
    }
    final timeout = request.arguments!['timeout'] as int? ?? 90000;
    final completer = Completer<({Uri dtdUri, int pid})>();

    log(
      LoggingLevel.debug,
      'Launching app with root: $root, target: $target, device: $device',
    );

    Process? process;
    try {
      process = await processManager.start(
        [
          sdk.flutterExecutablePath,
          'run',
          '--print-dtd',
          '--machine',
          '--device-id',
          device,
          ...args,
          if (target != null) ...['--target', target],
        ],
        workingDirectory: root,
        mode: ProcessStartMode.normal,
      );
      _runningApps[process.pid] = _RunningApp(process);
      log(
        LoggingLevel.info,
        'Launched Flutter application with PID: ${process.pid}',
      );

      final stdoutDone = Completer<void>();
      final stderrDone = Completer<void>();

      late StreamSubscription stdoutSubscription;
      late StreamSubscription stderrSubscription;

      void checkForDtdUri(String line) {
        line = line.trim();
        // Check for --machine output first.
        if (line.startsWith('[') && line.endsWith(']')) {
          // Looking for:
          // [{"event":"app.dtd","params":{"appId":"cd6c66eb-35e9-4ac1-96df-727540138346","uri":"ws://127.0.0.1:59548/3OpAaPw9i34="}}]
          try {
            final json =
                jsonDecode(line.substring(1, line.length - 1))
                    as Map<String, Object?>;
            if (json['event'] == 'app.dtd' && json['params'] != null) {
              final params = json['params'] as Map<String, Object?>;
              if (params['uri'] != null) {
                final dtdUri = Uri.parse(params['uri'] as String);
                log(LoggingLevel.debug, 'Found machine DTD URI: $dtdUri');
                completer.complete((dtdUri: dtdUri, pid: process!.pid));
              }
            }
          } on FormatException {
            // Ignore failures to parse the JSON or the URI.
            log(LoggingLevel.debug, 'Failed to parse $line for the DTD URI.');
          }
        }
      }

      stdoutSubscription = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              log(
                LoggingLevel.debug,
                '[flutter stdout ${process!.pid}]: $line',
              );
              _runningApps[process.pid]?.logs.add('[stdout] $line');
              checkForDtdUri(line);
            },
            onDone: stdoutDone.complete,
            onError: stdoutDone.completeError,
          );

      stderrSubscription = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              log(
                LoggingLevel.warning,
                '[flutter stderr ${process!.pid}]: $line',
              );
              _runningApps[process.pid]?.logs.add('[stderr] $line');
              checkForDtdUri(line);
            },
            onDone: stderrDone.complete,
            onError: stderrDone.completeError,
          );

      unawaited(
        process.exitCode.then((exitCode) async {
          // Wait for both streams to finish processing before potentially
          // completing the completer with an error.
          await Future.wait([stdoutDone.future, stderrDone.future]);

          log(
            LoggingLevel.info,
            'Flutter application ${process!.pid} exited with code $exitCode.',
          );
          if (!completer.isCompleted) {
            final logs = _runningApps[process.pid]?.logs ?? [];
            // Only output the last 500 lines of logs.
            final startLine = math.max(0, logs.length - 500);
            final logOutput = [
              if (startLine > 0) '[skipping $startLine log lines]...',
              ...logs.sublist(startLine),
            ];
            completer.completeError(
              'Flutter application exited with code $exitCode before the DTD '
              'URI was found, with log output:\n${logOutput.join('\n')}',
            );
          }
          _runningApps.remove(process.pid);

          // Cancel subscriptions after all processing is done.
          await stdoutSubscription.cancel();
          await stderrSubscription.cancel();
        }),
      );

      final result = await completer.future.timeout(
        Duration(milliseconds: timeout),
      );
      _runningApps[result.pid]?.dtdUri = result.dtdUri.toString();

      return CallToolResult(
        content: [
          TextContent(
            text:
                'Flutter application launched successfully with PID '
                '${result.pid} with the DTD URI ${result.dtdUri}',
          ),
        ],
        structuredContent: {
          ParameterNames.dtdUri: result.dtdUri.toString(),
          ParameterNames.pid: result.pid,
        },
      );
    } catch (e, s) {
      log(LoggingLevel.error, 'Error launching Flutter application: $e\n$s');
      if (process != null) {
        processManager.killPid(process.pid);
        // The exitCode handler will perform the rest of the cleanup.
      }
      return CallToolResult(
          isError: true,
          content: [
            TextContent(text: 'Failed to launch Flutter application: $e'),
          ],
        )
        ..failureReason = switch (e) {
          ProcessException() => CallToolFailureReason.processException,
          TimeoutException() => CallToolFailureReason.timeout,
          _ => null,
        };
    }
  }

  /// A tool to stop a running Flutter application.
  static final stopAppTool = Tool(
    name: ToolNames.stopApp.name,
    description:
        'Kills a running Flutter process started by the launch_app tool.',
    inputSchema: Schema.object(
      properties: {
        ParameterNames.pid: Schema.int(
          description: 'The process ID of the process to kill.',
        ),
      },
      required: [ParameterNames.pid],
      additionalProperties: false,
    ),
    outputSchema: Schema.object(
      properties: {
        'success': Schema.bool(
          description: 'Whether the process was killed successfully.',
        ),
      },
      required: ['success'],
    ),
  )..categories = [FeatureCategory.flutter];

  Future<CallToolResult> _stopApp(CallToolRequest request) async {
    final pid = request.arguments!['pid'] as int;
    log(LoggingLevel.info, 'Attempting to stop application with PID: $pid');
    final app = _runningApps[pid];

    if (app == null) {
      log(LoggingLevel.error, 'Application with PID $pid not found.');
      return CallToolResult(
        isError: true,
        content: [TextContent(text: 'Application with PID $pid not found.')],
      )..failureReason = CallToolFailureReason.applicationNotFound;
    }

    final success = processManager.killPid(pid);
    if (success) {
      log(
        LoggingLevel.info,
        'Successfully sent kill signal to application $pid.',
      );
    } else {
      log(
        LoggingLevel.warning,
        'Failed to send kill signal to application $pid.',
      );
    }

    return CallToolResult(
      content: [
        TextContent(
          text:
              'Application with PID $pid '
              '${success ? 'was stopped' : 'was unable to be stopped'}.',
        ),
      ],
      isError: !success,
      structuredContent: {'success': success},
    );
  }

  /// A tool to list available Flutter devices.
  static final listDevicesTool = Tool(
    name: ToolNames.listDevices.name,
    description: 'Lists available Flutter devices.',
    inputSchema: Schema.object(),
    outputSchema: Schema.object(
      properties: {
        'devices': Schema.list(
          description: 'A list of available device IDs.',
          items: ObjectSchema(
            properties: {
              'id': Schema.string(),
              'name': Schema.string(),
              'targetPlatform': Schema.string(),
            },
            additionalProperties: true,
          ),
        ),
      },
      required: ['devices'],
      additionalProperties: false,
    ),
  )..categories = [FeatureCategory.flutter, FeatureCategory.cli];

  Future<CallToolResult> _listDevices(CallToolRequest request) async {
    try {
      log(LoggingLevel.debug, 'Listing flutter devices.');
      final result = await processManager.run([
        sdk.flutterExecutablePath,
        'devices',
        '--machine',
      ]);

      if (result.exitCode != 0) {
        log(
          LoggingLevel.error,
          'Flutter devices command failed with exit code ${result.exitCode}. '
          'Stderr: ${result.stderr}',
        );
        return CallToolResult(
          isError: true,
          content: [
            TextContent(
              text: 'Failed to list Flutter devices: ${result.stderr}',
            ),
          ],
        )..failureReason = CallToolFailureReason.wrappedServiceIssue;
      }

      final stdout = result.stdout as String;
      if (stdout.isEmpty) {
        log(LoggingLevel.debug, 'No devices found.');
        return CallToolResult(
          content: [TextContent(text: 'No devices found.')],
          structuredContent: {'devices': <String>[]},
        );
      }

      final devices = (jsonDecode(stdout) as List)
          .cast<Map<String, dynamic>>()
          .toList();
      log(LoggingLevel.debug, 'Found devices: $devices');

      return CallToolResult(
        content: [
          TextContent(text: 'Found devices:\n'),
          for (var device in devices)
            TextContent(
              text:
                  '''
  - Device ID: ${device['id']}
    Name: ${device['name']}
    Target Platform: ${device['targetPlatform']}''',
            ),
        ],
        structuredContent: {'devices': devices},
      );
    } catch (e, s) {
      log(LoggingLevel.error, 'Error listing Flutter devices: $e\n$s');
      return CallToolResult(
        isError: true,
        content: [TextContent(text: 'Failed to list Flutter devices: $e')],
      )..failureReason = CallToolFailureReason.unhandledError;
    }
  }

  /// A tool to get the logs for a running Flutter application.
  static final getAppLogsTool = Tool(
    name: ToolNames.getAppLogs.name,
    description:
        'Returns the collected logs for a given flutter run process '
        'id. Can only retrieve logs started by the launch_app tool.',
    inputSchema: Schema.object(
      properties: {
        ParameterNames.pid: Schema.int(
          description:
              'The process ID of the flutter run process running the '
              'application.',
        ),
        'maxLines': Schema.int(
          description:
              'The maximum number of log lines to return from the end of the '
              'logs. Defaults to 500. If set to -1, all logs will be returned.',
        ),
      },
      required: [ParameterNames.pid],
      additionalProperties: false,
    ),
    outputSchema: Schema.object(
      properties: {
        'logs': Schema.list(
          description: 'The collected logs for the process.',
          items: Schema.string(),
        ),
      },
      required: ['logs'],
    ),
  )..categories = [FeatureCategory.flutter];

  Future<CallToolResult> _getAppLogs(CallToolRequest request) async {
    final pid = request.arguments!['pid'] as int;
    var maxLines = request.arguments!['maxLines'] as int? ?? 500;
    log(LoggingLevel.info, 'Getting logs for application with PID: $pid');
    var logs = _runningApps[pid]?.logs;

    if (logs == null) {
      log(LoggingLevel.error, 'Application with PID $pid not found.');
      return CallToolResult(
        isError: true,
        content: [TextContent(text: 'Application with PID $pid not found.')],
      )..failureReason = CallToolFailureReason.applicationNotFound;
    }

    if (maxLines == -1) {
      maxLines = logs.length;
    }
    if (maxLines > 0 && maxLines <= logs.length) {
      final startLine = logs.length - maxLines;
      logs = [
        if (startLine > 0) '[skipping $startLine log lines]...',
        ...logs.sublist(startLine),
      ];
    }

    return CallToolResult(
      content: [TextContent(text: logs.join('\n'))],
      structuredContent: {'logs': logs},
    );
  }

  /// A tool to list all running Flutter applications.
  static final listRunningAppsTool = Tool(
    name: ToolNames.listRunningApps.name,
    description:
        'Returns the list of running app process IDs and associated '
        'DTD URIs for apps started by the launch_app tool.',
    inputSchema: Schema.object(),
    outputSchema: Schema.object(
      properties: {
        ParameterNames.apps: Schema.list(
          description:
              'A list of running applications started by the '
              'launch_app tool.',
          items: Schema.object(
            properties: {
              ParameterNames.pid: Schema.int(
                description: 'The process ID of the application.',
              ),
              ParameterNames.dtdUri: Schema.string(
                description: 'The DTD URI of the application.',
              ),
            },
            required: [ParameterNames.pid, ParameterNames.dtdUri],
          ),
        ),
      },
      required: [ParameterNames.apps],
      additionalProperties: false,
    ),
  )..categories = [FeatureCategory.flutter];

  Future<CallToolResult> _listRunningApps(CallToolRequest request) async {
    final apps = _runningApps.entries
        .where((entry) => entry.value.dtdUri != null)
        .map((entry) {
          return {
            ParameterNames.pid: entry.key,
            ParameterNames.dtdUri: entry.value.dtdUri!,
          };
        })
        .toList();

    return CallToolResult(
      content: [
        TextContent(
          text:
              'Found ${apps.length} running application'
              '${apps.length == 1 ? '' : 's'}.\n'
              '${apps.map<String>((e) {
                return 'PID: ${e[ParameterNames.pid]}, DTD URI: ${e[ParameterNames.dtdUri]}';
              }).toList().join('\n')}',
        ),
      ],
      structuredContent: {ParameterNames.apps: apps},
    );
  }

  @override
  Future<void> shutdown() {
    log(LoggingLevel.info, 'Shutting down server, killing all processes.');
    for (final pid in _runningApps.keys) {
      log(LoggingLevel.debug, 'Killing process $pid.');
      processManager.killPid(pid);
    }
    _runningApps.clear();
    return super.shutdown();
  }
}
