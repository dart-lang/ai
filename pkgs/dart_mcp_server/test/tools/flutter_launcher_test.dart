// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:dart_mcp/client.dart';
import 'package:dart_mcp_server/src/server.dart';
import 'package:dart_mcp_server/src/utils/sdk.dart';
import 'package:fake_async/fake_async.dart';
import 'package:file/memory.dart';
import 'package:process/process.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart' as test;

void main() {
  test.group('DartMCPServer', () {
    late MemoryFileSystem fileSystem;
    const projectRoot = '/project';

    Future<({DartMCPServer server, ServerConnection client})>
    createServerAndClient({
      required ProcessManager processManager,
      required MemoryFileSystem fileSystem,
    }) async {
      final channel = StreamChannelController<String>();
      final server = DartMCPServer(
        channel.local,
        sdk: Sdk(
          flutterSdkPath: Platform.isWindows
              ? r'C:\path\to\flutter\sdk'
              : '/path/to/flutter/sdk',
          dartSdkPath: Platform.isWindows
              ? r'C:\path\to\flutter\sdk\bin\cache\dart-sdk'
              : '/path/to/flutter/sdk/bin/cache/dart-sdk',
        ),
        processManager: processManager,
        fileSystem: fileSystem,
      );
      final client = ServerConnection.fromStreamChannel(channel.foreign);
      return (server: server, client: client);
    }

    test.setUp(() {
      fileSystem = MemoryFileSystem();
      fileSystem.directory(projectRoot).createSync(recursive: true);
    });

    test.test('launch_app tool returns DTD URI and PID on success', () async {
      final dtdUri = 'ws://127.0.0.1:12345/abcdefg=';
      final processPid = 54321;
      final mockProcessManager = MockProcessManager();
      mockProcessManager.addCommand(
        Command(
          [
            Platform.isWindows
                ? r'C:\path\to\flutter\sdk\bin\cache\dart-sdk\bin\dart.exe'
                : '/path/to/flutter/sdk/bin/cache/dart-sdk/bin/dart',
            'language-server',
            '--protocol',
            'lsp',
          ],
          stdout:
              '''Content-Length: 145\r\n\r\n{"jsonrpc":"2.0","id":0,"result":{"capabilities":{"workspace":{"workspaceFolders":{"supported":true,"changeNotifications":true}},"workspaceSymbolProvider":true}}}''',
        ),
      );
      mockProcessManager.addCommand(
        Command(
          [
            Platform.isWindows
                ? r'C:\path\to\flutter\sdk\bin\flutter.bat'
                : '/path/to/flutter/sdk/bin/flutter',
            'run',
            '--print-dtd',
            '--machine',
            '--device-id',
            'test-device',
          ],
          stdout:
              '[{"event":"app.dtd","params":{'
              '"appId":"cd6c66eb-35e9-4ac1-96df-727540138346",'
              '"uri":"$dtdUri"}}]',
          pid: processPid,
        ),
      );
      final serverAndClient = await createServerAndClient(
        processManager: mockProcessManager,
        fileSystem: fileSystem,
      );
      final server = serverAndClient.server;
      final client = serverAndClient.client;

      // Initialize
      final initResult = await client.initialize(
        InitializeRequest(
          protocolVersion: ProtocolVersion.latestSupported,
          capabilities: ClientCapabilities(),
          clientInfo: Implementation(name: 'test_client', version: '1.0.0'),
        ),
      );
      test.expect(initResult.serverInfo.name, 'dart and flutter tooling');
      client.notifyInitialized();

      // Call the tool
      final result = await client.callTool(
        CallToolRequest(
          name: 'launch_app',
          arguments: {'root': projectRoot, 'device': 'test-device'},
        ),
      );
      test.expect(result.content, <Content>[
        Content.text(
          text:
              'Flutter application launched successfully with PID 54321 with the DTD URI ws://127.0.0.1:12345/abcdefg=',
        ),
      ]);
      test.expect(result.isError, test.isNot(true));
      test.expect(result.structuredContent, {
        'dtdUri': dtdUri,
        'pid': processPid,
      });
      await server.shutdown();
      await client.shutdown();
    });

    test.test('launch_app tool returns DTD URI and PID on success from '
        'stdout', () {
      fakeAsync((async) async {
        final dtdUri = 'ws://127.0.0.1:12345/abcdefg=';
        final processPid = 54321;
        final mockProcessManager = MockProcessManager();
        mockProcessManager.addCommand(
          Command(
            [
              Platform.isWindows
                  ? r'C:\path\to\flutter\sdk\bin\cache\dart-sdk\bin\dart.exe'
                  : '/path/to/flutter/sdk/bin/cache/dart-sdk/bin/dart',
              'language-server',
              '--protocol',
              'lsp',
            ],
            stdout:
                '''Content-Length: 145\r\n\r\n{"jsonrpc":"2.0","id":0,"result":{"capabilities":{"workspace":{"workspaceFolders":{"supported":true,"changeNotifications":true}},"workspaceSymbolProvider":true}}}''',
          ),
        );
        mockProcessManager.addCommand(
          Command(
            [
              Platform.isWindows
                  ? r'C:\path\to\flutter\sdk\bin\flutter.bat'
                  : '/path/to/flutter/sdk/bin/flutter',
              'run',
              '--print-dtd',
              '--machine',
              '--device-id',
              'test-device',
            ],
            stdout: 'The Dart Tooling Daemon is available at: $dtdUri\n',
            pid: processPid,
          ),
        );

        final serverAndClient = await createServerAndClient(
          processManager: mockProcessManager,
          fileSystem: fileSystem,
        );
        final server = serverAndClient.server;
        final client = serverAndClient.client;
        async.flushMicrotasks();

        // Initialize
        final initResult = await client.initialize(
          InitializeRequest(
            protocolVersion: ProtocolVersion.latestSupported,
            capabilities: ClientCapabilities(),
            clientInfo: Implementation(name: 'test_client', version: '1.0.0'),
          ),
        );
        test.expect(initResult.serverInfo.name, 'dart and flutter tooling');
        client.notifyInitialized();
        async.flushMicrotasks();

        // Call the tool
        final result = await client.callTool(
          CallToolRequest(
            name: 'launch_app',
            arguments: {'root': projectRoot, 'device': 'test-device'},
          ),
        );
        async.flushMicrotasks();

        test.expect(result.content, <Content>[
          Content.text(
            text:
                'Flutter application launched successfully with PID 54321 with the DTD URI ws://127.0.0.1:12345/abcdefg=',
          ),
        ]);
        test.expect(result.isError, test.isNot(true));
        test.expect(result.structuredContent, {
          'dtdUri': dtdUri,
          'pid': processPid,
        });

        await server.shutdown();
        await client.shutdown();
        async.flushMicrotasks();
      });
    });

    test.test('launch_app tool returns DTD URI and PID on success from '
        '--machine output', () async {
      final dtdUri = 'ws://127.0.0.1:12345/abcdefg=';
      final processPid = 54321;
      final mockProcessManager = MockProcessManager();
      mockProcessManager.addCommand(
        Command(
          [
            Platform.isWindows
                ? r'C:\path\to\flutter\sdk\bin\cache\dart-sdk\bin\dart.exe'
                : '/path/to/flutter/sdk/bin/cache/dart-sdk/bin/dart',
            'language-server',
            '--protocol',
            'lsp',
          ],
          stdout:
              '''Content-Length: 145\r\n\r\n{"jsonrpc":"2.0","id":0,"result":{"capabilities":{"workspace":{"workspaceFolders":{"supported":true,"changeNotifications":true}},"workspaceSymbolProvider":true}}}''',
        ),
      );
      mockProcessManager.addCommand(
        Command(
          [
            Platform.isWindows
                ? r'C:\path\to\flutter\sdk\bin\flutter.bat'
                : '/path/to/flutter/sdk/bin/flutter',
            'run',
            '--print-dtd',
            '--machine',
            '--device-id',
            'test-device',
          ],
          stdout:
              '[{"event":"app.dtd","params":{'
              '"appId":"cd6c66eb-35e9-4ac1-96df-727540138346",'
              '"uri":"$dtdUri"}}]',
          pid: processPid,
        ),
      );
      final serverAndClient = await createServerAndClient(
        processManager: mockProcessManager,
        fileSystem: fileSystem,
      );
      final server = serverAndClient.server;
      final client = serverAndClient.client;

      // Initialize
      final initResult = await client.initialize(
        InitializeRequest(
          protocolVersion: ProtocolVersion.latestSupported,
          capabilities: ClientCapabilities(),
          clientInfo: Implementation(name: 'test_client', version: '1.0.0'),
        ),
      );
      test.expect(initResult.serverInfo.name, 'dart and flutter tooling');
      client.notifyInitialized();

      // Call the tool
      final result = await client.callTool(
        CallToolRequest(
          name: 'launch_app',
          arguments: {'root': projectRoot, 'device': 'test-device'},
        ),
      );

      test.expect(result.content, <Content>[
        Content.text(
          text:
              'Flutter application launched successfully with PID 54321 with the DTD URI ws://127.0.0.1:12345/abcdefg=',
        ),
      ]);
      test.expect(result.isError, test.isNot(true));
      test.expect(result.structuredContent, {
        'dtdUri': dtdUri,
        'pid': processPid,
      });
      await server.shutdown();
      await client.shutdown();
    });

    test.test('launch_app tool fails when process exits early', () async {
      final mockProcessManager = MockProcessManager();
      mockProcessManager.addCommand(
        Command(
          [
            Platform.isWindows
                ? r'C:\path\to\flutter\sdk\bin\cache\dart-sdk\bin\dart.exe'
                : '/path/to/flutter/sdk/bin/cache/dart-sdk/bin/dart',
            'language-server',
            '--protocol',
            'lsp',
          ],
          stdout:
              '''Content-Length: 145\r\n\r\n{"jsonrpc":"2.0","id":0,"result":{"capabilities":{"workspace":{"workspaceFolders":{"supported":true,"changeNotifications":true}},"workspaceSymbolProvider":true}}}''',
        ),
      );
      mockProcessManager.addCommand(
        Command(
          [
            Platform.isWindows
                ? r'C:\path\to\flutter\sdk\bin\flutter.bat'
                : '/path/to/flutter/sdk/bin/flutter',
            'run',
            '--print-dtd',
            '--machine',
            '--device-id',
            'test-device',
          ],
          stderr: 'Something went wrong',
          exitCode: Future.value(1),
        ),
      );
      final serverAndClient = await createServerAndClient(
        processManager: mockProcessManager,
        fileSystem: fileSystem,
      );
      final server = serverAndClient.server;
      final client = serverAndClient.client;

      // Initialize
      await client.initialize(
        InitializeRequest(
          protocolVersion: ProtocolVersion.latestSupported,
          capabilities: ClientCapabilities(),
          clientInfo: Implementation(name: 'test_client', version: '1.0.0'),
        ),
      );
      client.notifyInitialized();

      // Call the tool
      final result = await client.callTool(
        CallToolRequest(
          name: 'launch_app',
          arguments: {'root': projectRoot, 'device': 'test-device'},
        ),
      );

      test.expect(result.isError, true);
      final textOutput = result.content as List<TextContent>;
      test.expect(
        textOutput.map((context) => context.text).toList().join('\n'),
        test.stringContainsInOrder([
          'Flutter application exited with code 1 before the DTD URI was found',
          'with log output',
          'Something went wrong',
        ]),
      );
      await server.shutdown();
      await client.shutdown();
    });

    test.test('launch_app tool times out if DTD URI is not found', () {
      fakeAsync((async) {
        // Setup mocks
        final mockProcessManager = MockProcessManager();
        mockProcessManager.addCommand(
          Command(
            [
              Platform.isWindows
                  ? r'C:\path\to\flutter\sdk\bin\cache\dart-sdk\bin\dart.exe'
                  : '/path/to/flutter/sdk/bin/cache/dart-sdk/bin/dart',
              'language-server',
              '--protocol',
              'lsp',
            ],
            stdout:
                '''Content-Length: 145\r\n\r\n{"jsonrpc":"2.0","id":0,"result":{"capabilities":{"workspace":{"workspaceFolders":{"supported":true,"changeNotifications":true}},"workspaceSymbolProvider":true}}}''',
          ),
        );
        final processPid = 54321;
        mockProcessManager.addCommand(
          Command(
            [
              Platform.isWindows
                  ? r'C:\path\to\flutter\sdk\bin\flutter.bat'
                  : '/path/to/flutter/sdk/bin/flutter',
              'run',
              '--print-dtd',
              '--machine',
              '--device-id',
              'test-device',
            ],
            stdout: 'Some output without DTD URI',
            pid: processPid,
          ),
        );

        // Create server and client
        late DartMCPServer server;
        late ServerConnection client;
        var serverAndClientReady = false;
        createServerAndClient(
          processManager: mockProcessManager,
          fileSystem: fileSystem,
        ).then((sc) {
          server = sc.server;
          client = sc.client;
          serverAndClientReady = true;
        });
        async.flushMicrotasks();
        test.expect(serverAndClientReady, true);

        // Initialize
        var initialized = false;
        client
            .initialize(
              InitializeRequest(
                protocolVersion: ProtocolVersion.latestSupported,
                capabilities: ClientCapabilities(),
                clientInfo: Implementation(
                  name: 'test_client',
                  version: '1.0.0',
                ),
              ),
            )
            .then((_) {
              client.notifyInitialized();
              initialized = true;
            });
        async.flushMicrotasks();
        test.expect(initialized, true);

        // Call the tool
        late CallToolResult result;
        var completed = false;
        client
            .callTool(
              CallToolRequest(
                name: 'launch_app',
                arguments: {'root': projectRoot, 'device': 'test-device'},
              ),
            )
            .then((res) {
              result = res;
              completed = true;
            });

        // Elapse time to trigger timeout
        async.elapse(const Duration(seconds: 91));
        async.flushMicrotasks();

        test.expect(completed, true);
        test.expect(result.isError, true);
        final textOutput = result.content as List<TextContent>;
        test.expect(
          textOutput.first.text,
          test.stringContainsInOrder([
            'Failed to launch Flutter application',
            'TimeoutException',
          ]),
        );
        test.expect(mockProcessManager.killedPids, [processPid]);

        server.shutdown();
        client.shutdown();
        async.flushMicrotasks();
      });
    });

    test.test('stop_app tool stops a running app', () async {
      final dtdUri = 'ws://127.0.0.1:12345/abcdefg=';
      final processPid = 54321;
      final mockProcessManager = MockProcessManager();
      mockProcessManager.addCommand(
        Command(
          [
            Platform.isWindows
                ? r'C:\path\to\flutter\sdk\bin\cache\dart-sdk\bin\dart.exe'
                : '/path/to/flutter/sdk/bin/cache/dart-sdk/bin/dart',
            'language-server',
            '--protocol',
            'lsp',
          ],
          stdout:
              '''Content-Length: 145\r\n\r\n{"jsonrpc":"2.0","id":0,"result":{"capabilities":{"workspace":{"workspaceFolders":{"supported":true,"changeNotifications":true}},"workspaceSymbolProvider":true}}}''',
        ),
      );
      mockProcessManager.addCommand(
        Command(
          [
            Platform.isWindows
                ? r'C:\path\to\flutter\sdk\bin\flutter.bat'
                : '/path/to/flutter/sdk/bin/flutter',
            'run',
            '--print-dtd',
            '--machine',
            '--device-id',
            'test-device',
          ],
          stdout:
              '[{"event":"app.dtd","params":{'
              '"appId":"cd6c66eb-35e9-4ac1-96df-727540138346",'
              '"uri":"$dtdUri"}}]',
          pid: processPid,
        ),
      );
      final serverAndClient = await createServerAndClient(
        processManager: mockProcessManager,
        fileSystem: fileSystem,
      );
      final server = serverAndClient.server;
      final client = serverAndClient.client;

      // Initialize and launch the app
      await client.initialize(
        InitializeRequest(
          protocolVersion: ProtocolVersion.latestSupported,
          capabilities: ClientCapabilities(),
          clientInfo: Implementation(name: 'test_client', version: '1.0.0'),
        ),
      );
      client.notifyInitialized();
      await client.callTool(
        CallToolRequest(
          name: 'launch_app',
          arguments: {'root': projectRoot, 'device': 'test-device'},
        ),
      );

      // Stop the app
      final result = await client.callTool(
        CallToolRequest(name: 'stop_app', arguments: {'pid': processPid}),
      );

      test.expect(result.isError, test.isNot(true));
      test.expect(result.structuredContent, {'success': true});
      test.expect(mockProcessManager.killedPids, [processPid]);
      await server.shutdown();
      await client.shutdown();
    });

    test.test('get_app_logs tool respects maxLines', () async {
      final dtdUri = 'ws://127.0.0.1:12345/abcdefg=';
      final processPid = 54321;
      final mockProcessManager = MockProcessManager();
      mockProcessManager.addCommand(
        Command(
          [
            Platform.isWindows
                ? r'C:\path\to\flutter\sdk\bin\cache\dart-sdk\bin\dart.exe'
                : '/path/to/flutter/sdk/bin/cache/dart-sdk/bin/dart',
            'language-server',
            '--protocol',
            'lsp',
          ],
          stdout:
              '''Content-Length: 145\r\n\r\n{"jsonrpc":"2.0","id":0,"result":{"capabilities":{"workspace":{"workspaceFolders":{"supported":true,"changeNotifications":true}},"workspaceSymbolProvider":true}}}''',
        ),
      );
      mockProcessManager.addCommand(
        Command(
          [
            Platform.isWindows
                ? r'C:\path\to\flutter\sdk\bin\flutter.bat'
                : '/path/to/flutter/sdk/bin/flutter',
            'run',
            '--print-dtd',
            '--machine',
            '--device-id',
            'test-device',
          ],
          stdout:
              'line 1\nline 2\nline 3\n'
              '[{"event":"app.dtd","params":{'
              '"appId":"cd6c66eb-35e9-4ac1-96df-727540138346",'
              '"uri":"$dtdUri"}}]',
          pid: processPid,
        ),
      );
      final serverAndClient = await createServerAndClient(
        processManager: mockProcessManager,
        fileSystem: fileSystem,
      );
      final server = serverAndClient.server;
      final client = serverAndClient.client;

      // Initialize and launch the app
      await client.initialize(
        InitializeRequest(
          protocolVersion: ProtocolVersion.latestSupported,
          capabilities: ClientCapabilities(),
          clientInfo: Implementation(name: 'test_client', version: '1.0.0'),
        ),
      );
      client.notifyInitialized();
      await client.callTool(
        CallToolRequest(
          name: 'launch_app',
          arguments: {'root': projectRoot, 'device': 'test-device'},
        ),
      );

      // Get the logs
      final result = await client.callTool(
        CallToolRequest(
          name: 'get_app_logs',
          arguments: {'pid': processPid, 'maxLines': 2},
        ),
      );

      test.expect(result.isError, test.isNot(true));
      test.expect(result.structuredContent, {
        'logs': [
          '[skipping 2 log lines]...',
          '[stdout] line 3',
          '[stdout] [{"event":"app.dtd","params":{"appId":"cd6c66eb-35e9-4ac1-96df-727540138346","uri":"ws://127.0.0.1:12345/abcdefg="}}]',
        ],
      });
      await server.shutdown();
      await client.shutdown();
    });

    test.test('list_devices tool returns available devices', () async {
      final mockProcessManager = MockProcessManager();
      mockProcessManager.addCommand(
        Command(
          [
            Platform.isWindows
                ? r'C:\path\to\flutter\sdk\bin\cache\dart-sdk\bin\dart.exe'
                : '/path/to/flutter/sdk/bin/cache/dart-sdk/bin/dart',
            'language-server',
            '--protocol',
            'lsp',
          ],
          stdout:
              '''Content-Length: 145\r\n\r\n{"jsonrpc":"2.0","id":0,"result":{"capabilities":{"workspace":{"workspaceFolders":{"supported":true,"changeNotifications":true}},"workspaceSymbolProvider":true}}}''',
        ),
      );
      mockProcessManager.addCommand(
        Command(
          [
            Platform.isWindows
                ? r'C:\path\to\flutter\sdk\bin\flutter.bat'
                : '/path/to/flutter/sdk/bin/flutter',
            'devices',
            '--machine',
          ],
          stdout: jsonEncode([
            {'id': 'test-device-1'},
            {'id': 'test-device-2'},
          ]),
        ),
      );
      final serverAndClient = await createServerAndClient(
        processManager: mockProcessManager,
        fileSystem: fileSystem,
      );
      final server = serverAndClient.server;
      final client = serverAndClient.client;

      // Initialize
      await client.initialize(
        InitializeRequest(
          protocolVersion: ProtocolVersion.latestSupported,
          capabilities: ClientCapabilities(),
          clientInfo: Implementation(name: 'test_client', version: '1.0.0'),
        ),
      );
      client.notifyInitialized();

      // List devices
      final result = await client.callTool(
        CallToolRequest(name: 'list_devices', arguments: {}),
      );

      test.expect(result.isError, test.isNot(true));
      test.expect(result.structuredContent, {
        'devices': ['test-device-1', 'test-device-2'],
      });
      await server.shutdown();
      await client.shutdown();
    });
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
