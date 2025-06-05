// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io' hide File;
import 'dart:io' as io show File;

import 'package:async/async.dart';
import 'package:dart_mcp/client.dart';
import 'package:dart_mcp_server/src/mixins/dtd.dart';
import 'package:dart_mcp_server/src/server.dart';
import 'package:dart_mcp_server/src/utils/constants.dart';
import 'package:dart_mcp_server/src/utils/sdk.dart';
import 'package:dtd/dtd.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:path/path.dart' as p;
import 'package:process/process.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';
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
  final FileSystem fileSystem;
  final Sdk sdk;

  ServerConnection get mcpServerConnection =>
      serverConnectionPair.serverConnection;

  TestHarness._(
    this.mcpClient,
    this.serverConnectionPair,
    this.fakeEditorExtension,
    this.fileSystem,
    this.sdk,
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
  static Future<TestHarness> start({
    bool inProcess = false,
    FileSystem? fileSystem,
  }) async {
    final sdk = Sdk.find(
      dartSdkPath: Platform.environment['DART_SDK'],
      flutterSdkPath: Platform.environment['FLUTTER_SDK'],
    );
    fileSystem ??= const LocalFileSystem();

    final mcpClient = DartToolingMCPClient();
    addTearDown(mcpClient.shutdown);

    final serverConnectionPair = await _initializeMCPServer(
      mcpClient,
      inProcess,
      fileSystem,
      sdk,
    );
    final connection = serverConnectionPair.serverConnection;
    connection.onLog.listen((log) {
      printOnFailure('MCP Server Log: $log');
    });

    final fakeEditorExtension = await FakeEditorExtension.connect(sdk);
    addTearDown(fakeEditorExtension.shutdown);

    return TestHarness._(
      mcpClient,
      serverConnectionPair,
      fakeEditorExtension,
      fileSystem,
      sdk,
    );
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
      sdk: sdk,
    );
    await fakeEditorExtension.addDebugSession(session);
    final root = rootForPath(projectRoot);
    final roots = (await mcpClient.handleListRoots(ListRootsRequest())).roots;
    if (!roots.any((r) => r.uri == root.uri)) {
      mcpClient.addRoot(root);
    }
    return session;
  }

  /// Creates a canonical [Root] object for a given [projectPath].
  Root rootForPath(String projectPath) =>
      Root(uri: fileSystem.directory(projectPath).absolute.uri.toString());

  /// Stops an app debug session.
  Future<void> stopDebugSession(AppDebugSession session) async {
    await fakeEditorExtension.removeDebugSession(session);
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
        arguments: {ParameterNames.uri: fakeEditorExtension.dtdUri},
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
    bool expectError = false,
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
      expectError ? true : isNot(true),
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
  final String id;

  AppDebugSession._({
    required this.appProcess,
    required this.vmServiceUri,
    required this.projectRoot,
    required this.appPath,
    required this.isFlutter,
    required this.id,
  });

  static Future<AppDebugSession> _start(
    String projectRoot,
    String appPath, {
    List<String> args = const [],
    required bool isFlutter,
    required Sdk sdk,
  }) async {
    final process = await TestProcess.start(
      isFlutter ? sdk.flutterExecutablePath : sdk.dartExecutablePath,
      [
        'run',
        '--no${isFlutter ? '' : '-serve'}-devtools',
        if (!isFlutter) '--enable-vm-service=0',
        if (isFlutter) ...['-d', 'flutter-tester'],
        appPath,
        ...args,
      ],
      workingDirectory: projectRoot,
    );

    addTearDown(() async {
      await kill(process, isFlutter);
    });

    String? vmServiceUri;
    final stdout = StreamQueue(process.stdoutStream());
    while (vmServiceUri == null && await stdout.hasNext) {
      final line = await stdout.next;
      final serviceString = isFlutter
          ? 'A Dart VM Service'
          : 'The Dart VM service';
      if (line.contains(serviceString)) {
        vmServiceUri = line
            .substring(line.indexOf('http:'))
            .replaceFirst('http:', 'ws:');
        await stdout.cancel();
      }
    }
    if (vmServiceUri == null) {
      throw StateError(
        'Failed to read vm service URI from the '
        '`${isFlutter ? 'flutter' : 'dart'} run` output',
      );
    }
    return AppDebugSession._(
      appProcess: process,
      vmServiceUri: vmServiceUri,
      projectRoot: projectRoot,
      appPath: appPath,
      isFlutter: isFlutter,
      id: FakeEditorExtension.nextId.toString(),
    );
  }

  static Future<void> kill(TestProcess process, bool isFlutter) async {
    if (isFlutter) {
      process.stdin.writeln('q');
      await process.shouldExit(0);
    } else {
      unawaited(process.kill());
      await process.shouldExit(anyOf(0, Platform.isWindows ? -1 : -9));
    }
  }

  /// Returns this as the Editor service representation.
  DebugSession asEditorDebugSession({required bool includeVmServiceUri}) =>
      DebugSession(
        debuggerType: isFlutter ? 'Flutter' : 'Dart',
        id: id,
        name: 'Test app',
        projectRootPath: projectRoot,
        vmServiceUri: includeVmServiceUri ? vmServiceUri : null,
      );
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
  Iterable<AppDebugSession> get debugSessions => _debugSessions;
  final List<AppDebugSession> _debugSessions = [];
  final TestProcess dtdProcess;
  final DartToolingDaemon dtd;
  final String dtdUri;

  FakeEditorExtension._(this.dtd, this.dtdProcess, this.dtdUri);

  static int get nextId => ++_nextId;
  static int _nextId = 0;

  static Future<FakeEditorExtension> connect(Sdk sdk) async {
    final dtdProcess = await TestProcess.start(sdk.dartExecutablePath, [
      'tooling-daemon',
    ]);
    final dtdUri = await _getDTDUri(dtdProcess);
    final dtd = await DartToolingDaemon.connect(Uri.parse(dtdUri));
    final extension = FakeEditorExtension._(dtd, dtdProcess, dtdUri);
    await extension._registerService();
    return extension;
  }

  Future<void> addDebugSession(AppDebugSession session) async {
    _debugSessions.add(session);
    await dtd.postEvent(
      'Editor',
      'debugSessionStarted',
      session.asEditorDebugSession(includeVmServiceUri: false),
    );
    // Fake a delay between session start and session ready (vm service URI is
    // known).
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await dtd.postEvent(
      'Editor',
      'debugSessionChanged',
      session.asEditorDebugSession(includeVmServiceUri: true),
    );
  }

  Future<void> removeDebugSession(AppDebugSession session) async {
    if (_debugSessions.remove(session)) {
      await dtd.postEvent('Editor', 'debugSessionStopped', {
        'debugSessionId': session.id,
      });
    }
  }

  Future<void> _registerService() async {
    await dtd.registerService('Editor', 'getDebugSessions', (request) async {
      return GetDebugSessionsResponse(
        debugSessions: [
          for (var debugSession in debugSessions)
            debugSession.asEditorDebugSession(includeVmServiceUri: true),
        ],
      );
    });
  }

  Future<void> shutdown() async {
    await _debugSessions.toList().map(removeDebugSession).wait;
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

typedef ServerConnectionPair = ({
  ServerConnection serverConnection,
  DartMCPServer? server,
});

/// Starts up the [DartMCPServer] and connects [client] to it.
///
/// Also handles the full intialization handshake between the client and
/// server.
Future<ServerConnectionPair> _initializeMCPServer(
  MCPClient client,
  bool inProcess,
  FileSystem fileSystem,
  Sdk sdk,
) async {
  ServerConnection connection;
  DartMCPServer? server;
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
    server = DartMCPServer(
      serverChannel,
      processManager: TestProcessManager(),
      fileSystem: fileSystem,
      sdk: sdk,
    );
    addTearDown(server.shutdown);
    connection = client.connectServer(clientChannel);
  } else {
    connection = await client.connectStdioServer(sdk.dartExecutablePath, [
      'pub', // Using `pub` gives us incremental compilation
      'run',
      'bin/main.dart',
    ]);
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

final counterAppPath = p.join('test_fixtures', 'counter_app');

final dartCliAppsPath = p.join('test_fixtures', 'dart_cli_app');

/// A test wrapper around [LocalProcessManager] that stores commands locally
/// instead of running them by spawning sub-processes.
class TestProcessManager extends LocalProcessManager {
  TestProcessManager() {
    addTearDown(reset);
  }

  final commandsRan = <({List<Object> command, String? workingDirectory})>[];

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
    commandsRan.add((command: command, workingDirectory: workingDirectory));
    return ProcessResult(nextPid++, 0, '', '');
  }

  void reset() {
    commandsRan.clear();
  }
}

Matcher equalsCommand(
  ({List<Object> command, String? workingDirectory}) command,
) => _CommandMatcher(command);

class _CommandMatcher extends Matcher {
  final ({List<Object> command, String? workingDirectory}) value;

  _CommandMatcher(this.value);

  @override
  Description describe(Description description) => description;

  @override
  bool matches(Object? item, Map matchState) {
    if (item is! ({List<Object> command, String? workingDirectory})) {
      return false;
    }
    if (item.workingDirectory != value.workingDirectory) {
      return false;
    }
    if (!equals(value.command).matches(item.command, matchState)) {
      return false;
    }
    return true;
  }
}

extension RootPath on Root {
  /// Get the OS specific file path for this root.
  String get path => io.File.fromUri(Uri.parse(uri)).path;
}
