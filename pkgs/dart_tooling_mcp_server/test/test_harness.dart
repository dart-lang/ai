// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:dart_mcp/client.dart';
import 'package:dart_tooling_mcp_server/src/mixins/dtd.dart';
import 'package:dart_tooling_mcp_server/src/server.dart';
import 'package:dtd/dtd.dart';
import 'package:path/path.dart' as p;
import 'package:process/process.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;
import 'package:test_process/test_process.dart';

/// A full environment for integration testing the MCP server.
///
/// - Runs the counter app at `test_fixtures/counter_app` using `flutter run`.
/// - Connects to the dtd service and registers a fake `Editor.getDebugSessions`
///   extension method on it to mimic the DartCode extension.
/// - Sets up the MCP client and server, and fully initializes the connection
///   between them. Includes a debug mode for running them both in process to
///   allow for breakpoints, but the default mode is to run the server in a
///   separate process.
class TestHarness {
  final FakeEditorExtension fakeEditorExtension;
  final DartToolingMCPClient mcpClient;
  final ServerConnectionPair serverConnectionPair;
  ServerConnection get mcpServerConnection =>
      serverConnectionPair.serverConnection;

  TestHarness._(
    this.mcpClient,
    this.serverConnectionPair,
    this.fakeEditorExtension,
  );

  /// Starts a Dart Tooling Daemon as well as an MCP client and server, and
  /// a [FakeEditorExtension] to manage registering debug sessions.
  ///
  /// Handles the initialization handshake between the MCP client and server as
  /// well.
  ///
  /// By default this will run with the MCP server compiled as a separate binary
  /// to mimic as closely as possible the real world behavior. Set `inProcess`
  /// to true to run the MCP server in the same isolate as the test. This will
  /// allow for testing the logic inside of the MCP server support mixins.
  /// Setting this to true is also useful for local debugging of tests that run
  /// the MCP server as a separate binary, since breakpoints will work when the
  /// MCP server is ran in process.
  ///
  /// Use [startDebugSession] to start up apps and connect to them.
  static Future<TestHarness> start({bool inProcess = false}) async {
    final mcpClient = DartToolingMCPClient();
    addTearDown(mcpClient.shutdown);

    final serverConnectionPair = await _initializeMCPServer(
      mcpClient,
      inProcess,
    );
    final connection = serverConnectionPair.serverConnection;
    connection.onLog.listen((log) {
      printOnFailure('MCP Server Log: $log');
    });

    final fakeEditorExtension = await FakeEditorExtension.connect();
    addTearDown(fakeEditorExtension.shutdown);

    return TestHarness._(mcpClient, serverConnectionPair, fakeEditorExtension);
  }

  /// Starts an app debug session.
  Future<AppDebugSession> startDebugSession(
    String projectRoot,
    String appPath, {
    required bool isFlutter,
    List<String> args = const [],
  }) async {
    final session = await AppDebugSession._start(
      projectRoot,
      appPath,
      isFlutter: isFlutter,
      args: args,
    );
    fakeEditorExtension.debugSessions.add(session);
    final root = rootForPath(projectRoot);
    final roots = (await mcpClient.handleListRoots(ListRootsRequest())).roots;
    if (!roots.any((r) => r.uri == root.uri)) {
      mcpClient.addRoot(root);
    }
    unawaited(
      session.appProcess.exitCode.then((_) {
        fakeEditorExtension.debugSessions.remove(session);
      }),
    );
    return session;
  }

  /// Stops an app debug session.
  Future<void> stopDebugSession(AppDebugSession session) async {
    await AppDebugSession.kill(session.appProcess, session.isFlutter);
  }

  /// Connects the MCP server to the dart tooling daemon at the `dtdUri` from
  /// [fakeEditorExtension] using the "connectDartToolingDaemon" tool function.
  ///
  /// This mimics a user using the "copy DTD Uri from clipboard" action.
  Future<void> connectToDtd() async {
    final tools = (await mcpServerConnection.listTools()).tools;

    final connectTool = tools.singleWhere(
      (t) => t.name == DartToolingDaemonSupport.connectTool.name,
    );

    final result = await callToolWithRetry(
      CallToolRequest(
        name: connectTool.name,
        arguments: {'uri': fakeEditorExtension.dtdUri},
      ),
    );

    expect(result.isError, isNot(true), reason: result.content.join('\n'));
  }

  /// Sends [request] to [mcpServerConnection], retrying [maxTries] times.
  ///
  /// Some methods will fail if the DTD connection is not yet ready.
  Future<CallToolResult> callToolWithRetry(
    CallToolRequest request, {
    int maxTries = 5,
  }) async {
    var tryCount = 0;
    late CallToolResult lastResult;
    while (tryCount++ < maxTries) {
      lastResult = await mcpServerConnection.callTool(request);
      if (lastResult.isError != true) return lastResult;
      await Future<void>.delayed(Duration(milliseconds: 100 * tryCount));
    }
    expect(
      lastResult.isError,
      isNot(true),
      reason: lastResult.content.join('\n'),
    );
    return lastResult;
  }
}

/// The debug session for a single app.
///
/// Should be started using [TestHarness.startDebugSession].
final class AppDebugSession {
  final TestProcess appProcess;
  final String appPath;
  final String projectRoot;
  final String vmServiceUri;
  final bool isFlutter;

  AppDebugSession._({
    required this.appProcess,
    required this.vmServiceUri,
    required this.projectRoot,
    required this.appPath,
    required this.isFlutter,
  });

  static Future<AppDebugSession> _start(
    String projectRoot,
    String appPath, {
    List<String> args = const [],
    required bool isFlutter,
  }) async {
    final platform =
        Platform.isLinux
            ? 'linux'
            : Platform.isMacOS
            ? 'macos'
            : throw StateError(
              'unsupported platform, only mac and linux are supported',
            );
    final process = await TestProcess.start(isFlutter ? 'flutter' : 'dart', [
      'run',
      '--no${isFlutter ? '' : '-serve'}-devtools',
      if (!isFlutter) '--enable-vm-service',
      if (isFlutter) ...['-d', platform],
      appPath,
      ...args,
    ], workingDirectory: projectRoot);

    addTearDown(() async {
      await kill(process, isFlutter);
    });

    String? vmServiceUri;
    final stdout = StreamQueue(process.stdoutStream());
    while (vmServiceUri == null && await stdout.hasNext) {
      final line = await stdout.next;
      if (line.contains('A Dart VM Service')) {
        vmServiceUri = line
            .substring(line.indexOf('http:'))
            .replaceFirst('http:', 'ws:');
        await stdout.cancel();
      }
    }
    if (vmServiceUri == null) {
      throw StateError(
        'Failed to read vm service URI from the flutter run output',
      );
    }
    return AppDebugSession._(
      appProcess: process,
      vmServiceUri: vmServiceUri,
      projectRoot: projectRoot,
      appPath: appPath,
      isFlutter: isFlutter,
    );
  }

  static Future<void> kill(TestProcess process, bool isFlutter) async {
    if (isFlutter) {
      process.stdin.writeln('q');
    } else {
      unawaited(process.kill());
    }
    await process.shouldExit(0);
  }
}

/// A basic MCP client which is started as a part of the harness.
final class DartToolingMCPClient extends MCPClient with RootsSupport {
  DartToolingMCPClient()
    : super(
        ClientImplementation(
          name: 'test client for the dart tooling mcp server',
          version: '0.1.0',
        ),
      );
}

/// The dart tooling daemon currently expects to get vm service uris through
/// the `Editor.getDebugSessions` DTD extension.
///
/// This class registers a similar extension for a normal `flutter run` process,
/// without having the normal editor extension in place.
class FakeEditorExtension {
  final List<AppDebugSession> debugSessions = [];
  final TestProcess dtdProcess;
  final DartToolingDaemon dtd;
  final String dtdUri;
  int get nextId => ++_nextId;
  int _nextId = 0;

  FakeEditorExtension(this.dtd, this.dtdProcess, this.dtdUri) {
    _registerService();
  }

  static Future<FakeEditorExtension> connect() async {
    final dtdProcess = await TestProcess.start('dart', ['tooling-daemon']);
    final dtdUri = await _getDTDUri(dtdProcess);
    final dtd = await DartToolingDaemon.connect(Uri.parse(dtdUri));
    return FakeEditorExtension(dtd, dtdProcess, dtdUri);
  }

  void _registerService() async {
    await dtd.registerService('Editor', 'getDebugSessions', (request) async {
      return GetDebugSessionsResponse(
        debugSessions: [
          for (var debugSession in debugSessions)
            DebugSession(
              debuggerType: debugSession.isFlutter ? 'Flutter' : 'Dart',
              id: nextId.toString(),
              name: 'Test app',
              projectRootPath: debugSession.projectRoot,
              vmServiceUri: debugSession.vmServiceUri,
            ),
        ],
      );
    });
  }

  Future<void> shutdown() async {
    await dtdProcess.kill();
    await dtd.close();
  }
}

/// Reads DTD uri from the [dtdProcess] output.
Future<String> _getDTDUri(TestProcess dtdProcess) async {
  String? dtdUri;
  final stdout = StreamQueue(dtdProcess.stdoutStream());
  while (await stdout.hasNext) {
    final line = await stdout.next;
    const devtoolsLineStart = 'The Dart Tooling Daemon is listening on';
    if (line.startsWith(devtoolsLineStart)) {
      dtdUri = line.substring(line.indexOf('ws:'));
      await stdout.cancel();
      break;
    }
  }
  if (dtdUri == null) {
    throw StateError(
      'Failed to scrape the Dart Tooling Daemon URI from the process output.',
    );
  }

  return dtdUri;
}

/// Compiles the dart tooling mcp server to AOT and returns the location.
Future<String> _compileMCPServer() async {
  final filePath = d.path('main.exe');
  final result = await TestProcess.start(Platform.executable, [
    'compile',
    'exe',
    'bin/main.dart',
    '-o',
    filePath,
  ]);
  await result.shouldExit(0);
  return filePath;
}

typedef ServerConnectionPair =
    ({ServerConnection serverConnection, DartToolingMCPServer? server});

/// Starts up the [DartToolingMCPServer] and connects [client] to it.
///
/// Also handles the full intialization handshake between the client and
/// server.
Future<ServerConnectionPair> _initializeMCPServer(
  MCPClient client,
  bool inProcess,
) async {
  ServerConnection connection;
  DartToolingMCPServer? server;
  if (inProcess) {
    /// The client side of the communication channel - the stream is the
    /// incoming data and the sink is outgoing data.
    final clientController = StreamController<String>();

    /// The server side of the communication channel - the stream is the
    /// incoming data and the sink is outgoing data.
    final serverController = StreamController<String>();

    late final clientChannel = StreamChannel<String>.withCloseGuarantee(
      serverController.stream,
      clientController.sink,
    );
    late final serverChannel = StreamChannel<String>.withCloseGuarantee(
      clientController.stream,
      serverController.sink,
    );
    server = DartToolingMCPServer(
      channel: serverChannel,
      processManager: TestProcessManager(),
    );
    addTearDown(server.shutdown);
    connection = client.connectServer(clientChannel);
  } else {
    connection = await client.connectStdioServer(await _compileMCPServer(), []);
  }

  final initializeResult = await connection.initialize(
    InitializeRequest(
      protocolVersion: ProtocolVersion.latestSupported,
      capabilities: client.capabilities,
      clientInfo: client.implementation,
    ),
  );
  expect(initializeResult.protocolVersion, ProtocolVersion.latestSupported);
  connection.notifyInitialized(InitializedNotification());
  return (serverConnection: connection, server: server);
}

/// Creates a canonical [Root] object for a given [projectPath].
Root rootForPath(String projectPath) =>
    Root(uri: Directory(projectPath).absolute.uri.toString());

final counterAppPath = p.join('test_fixtures', 'counter_app');

final dartCliAppsPath = p.join('test_fixtures', 'dart_cli_app');

/// A test wrapper around [LocalProcessManager] that stores commands locally
/// instead of running them by spawning sub-processes.
class TestProcessManager extends LocalProcessManager {
  TestProcessManager() {
    addTearDown(reset);
  }

  final commandsRan = <List<Object>>[];

  int nextPid = 0;

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
    commandsRan.add(command);
    return ProcessResult(nextPid++, 0, '', '');
  }

  void reset() {
    commandsRan.clear();
  }
}
