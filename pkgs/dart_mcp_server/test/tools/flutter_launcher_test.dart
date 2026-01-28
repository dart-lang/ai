// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:dart_mcp/client.dart';
import 'package:dart_mcp_server/src/server.dart';
import 'package:dart_mcp_server/src/utils/analytics.dart';
import 'package:dart_mcp_server/src/utils/sdk.dart';
import 'package:file/memory.dart';
import 'package:process/process.dart';
import 'package:test/test.dart';
import 'package:unified_analytics/testing.dart';
import 'package:unified_analytics/unified_analytics.dart';

import '../test_harness.dart';

void main() {
  group('Flutter App Tools', () {
    late MemoryFileSystem fileSystem;
    const projectRoot = '/project';
    final dtdUri = 'ws://127.0.0.1:12345/abcdefg=';
    final processPid = 54321;
    late TestHarness testHarness;
    late DartMCPServer server;
    late ServerConnection client;
    late MockProcessManager mockProcessManager;
    final sdk = Sdk(
      flutterSdkPath: Platform.isWindows
          ? r'C:\path\to\flutter\sdk'
          : '/path/to/flutter/sdk',
      dartSdkPath: Platform.isWindows
          ? r'C:\path\to\flutter\sdk\bin\cache\dart-sdk'
          : '/path/to/flutter/sdk/bin/cache/dart-sdk',
    );

    // Sets up a flutter run mock call, with success case defaults.
    void mockFlutterRun({String? stdout, String? stderr, int? exitCode}) {
      mockProcessManager.addCommand(
        Command(
          [
            sdk.flutterExecutablePath,
            'run',
            '--print-dtd',
            '--machine',
            '--device-id',
            'test-device',
          ],
          stderr: stderr,
          stdout:
              stdout ??
              '[{"event":"app.dtd","params":{'
                  '"appId":"cd6c66eb-35e9-4ac1-96df-727540138346",'
                  '"uri":"$dtdUri"}}]',
          exitCode: exitCode != null ? Future.value(exitCode) : null,
          pid: processPid,
        ),
      );
    }

    setUp(() async {
      fileSystem = MemoryFileSystem();
      fileSystem.directory(projectRoot).createSync(recursive: true);
      mockProcessManager = MockProcessManager();
      mockProcessManager.addCommand(
        Command(
          [sdk.dartExecutablePath, 'language-server', '--protocol', 'lsp'],
          stdout:
              '''Content-Length: 145\r\n\r\n{"jsonrpc":"2.0","id":0,"result":{"capabilities":{"workspace":{"workspaceFolders":{"supported":true,"changeNotifications":true}},"workspaceSymbolProvider":true}}}''',
        ),
      );
      mockProcessManager.addCommand(
        Command(
          [sdk.dartExecutablePath, 'tooling-daemon', '--machine'],
          stdout: jsonEncode({
            'tooling_daemon_details': {
              'uri': dtdUri,
              'trusted_client_secret': 'abcdefg',
            },
          }),
        ),
      );
      testHarness = await TestHarness.start(
        inProcess: true,
        processManager: mockProcessManager,
        fileSystem: fileSystem,
        sdk: sdk,
        startFakeEditorExtension: false,
      );
      server = testHarness.serverConnectionPair.server!;
      client = testHarness.serverConnectionPair.serverConnection;
    });

    test('launch_app tool returns DTD URI and PID on success', () async {
      mockFlutterRun();
      final result = await client.callTool(
        CallToolRequest(
          name: 'launch_app',
          arguments: {'root': projectRoot, 'device': 'test-device'},
        ),
      );
      expect(result.content, <Content>[
        Content.text(
          text:
              'Flutter application launched successfully with PID 54321 with the DTD URI ws://127.0.0.1:12345/abcdefg=',
        ),
      ]);
      expect(result.isError, isNot(true));
      expect(result.structuredContent, {'dtdUri': dtdUri, 'pid': processPid});
      await server.shutdown();
      await client.shutdown();
    });

    test(
      'launch_app tool returns DTD URI and PID on success from  stdout',
      () async {
        mockFlutterRun();
        final result = await client.callTool(
          CallToolRequest(
            name: 'launch_app',
            arguments: {'root': projectRoot, 'device': 'test-device'},
          ),
        );

        expect(result.content, <Content>[
          Content.text(
            text:
                'Flutter application launched successfully with PID 54321 with the DTD URI ws://127.0.0.1:12345/abcdefg=',
          ),
        ]);
        expect(result.isError, isNot(true));
        expect(result.structuredContent, {'dtdUri': dtdUri, 'pid': processPid});
      },
    );

    test('launch_app tool returns DTD URI and PID on success from '
        '--machine output', () async {
      mockFlutterRun();
      final result = await client.callTool(
        CallToolRequest(
          name: 'launch_app',
          arguments: {'root': projectRoot, 'device': 'test-device'},
        ),
      );

      expect(result.content, <Content>[
        Content.text(
          text:
              'Flutter application launched successfully with PID 54321 with the DTD URI ws://127.0.0.1:12345/abcdefg=',
        ),
      ]);
      expect(result.isError, isNot(true));
      expect(result.structuredContent, {'dtdUri': dtdUri, 'pid': processPid});
    });

    test('launch_app tool fails when process exits early', () async {
      mockFlutterRun(exitCode: 1, stderr: 'Something went wrong', stdout: '');

      final result = await client.callTool(
        CallToolRequest(
          name: 'launch_app',
          arguments: {'root': projectRoot, 'device': 'test-device'},
        ),
      );

      expect(result.isError, true);
      final textOutput = result.content as List<TextContent>;
      expect(
        textOutput.map((context) => context.text).toList().join('\n'),
        stringContainsInOrder([
          'Flutter application exited with code 1 before the DTD URI was found',
          'with log output',
          'Something went wrong',
        ]),
      );
    });

    test('launch_app tool times out if DTD URI is not found', () async {
      mockFlutterRun(stdout: 'Some output without a DTD uri');
      final result = await client.callTool(
        CallToolRequest(
          name: 'launch_app',
          arguments: {
            'root': projectRoot,
            'device': 'test-device',
            'timeout': 1,
          },
        ),
      );

      expect(result.isError, true);
      final textOutput = result.content as List<TextContent>;
      expect(
        textOutput.first.text,
        stringContainsInOrder([
          'Failed to launch Flutter application',
          'TimeoutException',
        ]),
      );
      expect(mockProcessManager.killedPids, [processPid]);

      expect(
        (server.analytics! as FakeAnalytics).sentEvents.last,
        isA<Event>()
            .having((e) => e.eventName, 'eventName', DashEvent.dartMCPEvent)
            .having(
              (e) => e.eventData,
              'eventData',
              equals({
                'client': server.clientInfo.name,
                'clientVersion': server.clientInfo.version,
                'serverVersion': server.implementation.version,
                'type': AnalyticsEvent.callTool.name,
                'tool': 'launch_app',
                'success': false,
                'failureReason': CallToolFailureReason.timeout.name,
                'elapsedMilliseconds': isA<int>(),
              }),
            ),
      );
    });

    test('stop_app tool stops a running app', () async {
      mockFlutterRun();
      await client.callTool(
        CallToolRequest(
          name: 'launch_app',
          arguments: {'root': projectRoot, 'device': 'test-device'},
        ),
      );

      final result = await client.callTool(
        CallToolRequest(name: 'stop_app', arguments: {'pid': processPid}),
      );

      expect(result.isError, isNot(true));
      expect(result.structuredContent, {'success': true});
      expect(mockProcessManager.killedPids, [processPid]);
    });

    test('get_app_logs tool respects maxLines', () async {
      mockFlutterRun(
        stdout:
            'line 1\nline 2\nline 3\n'
            '[{"event":"app.dtd","params":{'
            '"appId":"cd6c66eb-35e9-4ac1-96df-727540138346",'
            '"uri":"$dtdUri"}}]',
      );
      await client.callTool(
        CallToolRequest(
          name: 'launch_app',
          arguments: {'root': projectRoot, 'device': 'test-device'},
        ),
      );

      final result = await client.callTool(
        CallToolRequest(
          name: 'get_app_logs',
          arguments: {'pid': processPid, 'maxLines': 2},
        ),
      );

      expect(result.isError, isNot(true));
      expect(result.structuredContent, {
        'logs': [
          '[skipping 2 log lines]...',
          '[stdout] line 3',
          '[stdout] [{"event":"app.dtd","params":{"appId":"cd6c66eb-35e9-4ac1-96df-727540138346","uri":"ws://127.0.0.1:12345/abcdefg="}}]',
        ],
      });
    });

    test('list_devices tool returns available devices', () async {
      mockProcessManager.addCommand(
        Command(
          [sdk.flutterExecutablePath, 'devices', '--machine'],
          stdout: jsonEncode([
            {
              'id': 'test-device-1',
              'name': 'Test Device 1',
              'targetPlatform': 'android',
            },
            {
              'id': 'test-device-2',
              'name': 'Test Device 2',
              'targetPlatform': 'ios',
            },
          ]),
        ),
      );

      final result = await client.callTool(
        CallToolRequest(name: 'list_devices', arguments: {}),
      );

      expect(result.isError, isNot(true));
      expect(result.structuredContent, {
        'devices': [
          {
            'id': 'test-device-1',
            'name': 'Test Device 1',
            'targetPlatform': 'android',
          },
          {
            'id': 'test-device-2',
            'name': 'Test Device 2',
            'targetPlatform': 'ios',
          },
        ],
      });
    });
  });

  test('Does not register tools with --tools=dart', () async {
    final testHarness = await TestHarness.start(
      inProcess: false,
      cliArgs: ['--tools', 'dart'],
    );
    final connection = testHarness.serverConnectionPair.serverConnection;

    final tools = (await connection.listTools()).tools;
    final unexpectedTools = [
      'launch_app',
      'stop_app',
      'list_devices',
      'get_app_logs',
      'list_running_apps',
      'flutter_driver',
    ];
    for (final name in unexpectedTools) {
      expect(
        tools,
        isNot(contains(predicate<Tool>((tool) => tool.name == name))),
      );
    }
    expect(tools, isNotEmpty);
  });
}

class Command {
  final List<String> command;
  final String? stdout;
  final String? stderr;
  final Future<int>? exitCode;
  final int pid;

  Command(
    this.command, {
    this.stdout,
    this.stderr,
    this.exitCode,
    this.pid = 12345,
  });
}

class MockProcessManager implements ProcessManager {
  final List<Command> _commands = [];
  final List<List<Object>> commands = [];
  final Map<int, MockProcess> runningProcesses = {};
  bool shouldThrowOnStart = false;
  bool killResult = true;
  final killedPids = <int>[];
  int _pidCounter = 12345;

  void addCommand(Command command) {
    _commands.add(command);
  }

  Command _findCommand(List<Object> command) {
    for (final cmd in _commands) {
      if (const ListEquality<Object>().equals(cmd.command, command)) {
        return cmd;
      }
    }
    throw Exception(
      'Command not mocked: $command. Mocked commands:\n${_commands.join('\n')}',
    );
  }

  @override
  Future<Process> start(
    List<Object> command, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) async {
    if (shouldThrowOnStart) {
      throw Exception('Failed to start process');
    }
    commands.add(command);
    final mockCommand = _findCommand(command);
    final pid = mockCommand.pid == 12345 ? _pidCounter++ : mockCommand.pid;
    final process = MockProcess(
      stdout: Stream.value(utf8.encode(mockCommand.stdout ?? '')),
      stderr: Stream.value(utf8.encode(mockCommand.stderr ?? '')),
      pid: pid,
      exitCodeFuture: mockCommand.exitCode,
    );
    runningProcesses[pid] = process;
    return process;
  }

  @override
  bool killPid(int pid, [ProcessSignal signal = ProcessSignal.sigterm]) {
    killedPids.add(pid);
    runningProcesses[pid]?.kill();
    return killResult;
  }

  @override
  Future<ProcessResult> run(
    List<Object> command, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Encoding? stdoutEncoding = systemEncoding,
    Encoding? stderrEncoding = systemEncoding,
  }) async {
    commands.add(command);
    final mockCommand = _findCommand(command);
    return ProcessResult(
      mockCommand.pid,
      await (mockCommand.exitCode ?? Future.value(0)),
      mockCommand.stdout ?? '',
      mockCommand.stderr ?? '',
    );
  }

  @override
  bool canRun(Object? executable, {String? workingDirectory}) => true;

  @override
  ProcessResult runSync(
    List<Object> command, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Encoding? stdoutEncoding = systemEncoding,
    Encoding? stderrEncoding = systemEncoding,
  }) {
    throw UnimplementedError();
  }
}

class MockProcess implements Process {
  @override
  final Stream<List<int>> stdout;
  @override
  final Stream<List<int>> stderr;
  @override
  final int pid;

  @override
  late final Future<int> exitCode;
  final Completer<int> exitCodeCompleter = Completer<int>();

  bool killed = false;

  MockProcess({
    required this.stdout,
    required this.stderr,
    required this.pid,
    Future<int>? exitCodeFuture,
  }) {
    exitCode = exitCodeFuture ?? exitCodeCompleter.future;
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    if (!exitCodeCompleter.isCompleted) {
      exitCodeCompleter.complete(-9); // SIGKILL
    }
    return true;
  }

  @override
  late final IOSink stdin = IOSink(StreamController<List<int>>().sink);
}
