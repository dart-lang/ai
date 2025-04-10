// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:async/async.dart';
import 'package:dart_mcp/client.dart';
import 'package:dart_tooling_mcp_server/src/mixins/dtd.dart';
import 'package:dart_tooling_mcp_server/src/server.dart';
import 'package:dtd/dtd.dart';
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
  final ServerConnection mcpServerConnection;
  final String dtdUri;

  TestHarness._(
    this.mcpClient,
    this.mcpServerConnection,
    this.fakeEditorExtension,
    this.dtdUri,
  );

  /// Starts a Dart Tooling Daemon as well as an MCP client and server, and
  /// a [FakeEditorExtension] to manage registering debug sessions.
  ///
  /// Handles the initialization handshake between the MCP client and server as
  /// well.
  ///
  /// By default this will run with the MCP server compiled as a separate binary
  /// to mimic as closely as possible the real world behavior. This makes it so
  /// breakpoints in the server don't work however, so you can set [debugMode]
  /// to `true` and we will run it in process instead, which allows breakpoints
  /// since everything is running in the same isolate.
  ///
  /// Use [startDebugSession] to start up apps and connect to them.
  static Future<TestHarness> start({
    @Deprecated('For debugging only, do not submit') bool debugMode = false,
  }) async {
    final mcpClient = DartToolingMCPClient();
    addTearDown(mcpClient.shutdown);
    final connection = await _initializeMCPServer(mcpClient, debugMode);
    connection.onLog.listen((log) {
      printOnFailure('MCP Server Log: $log');
    });

    final dtdProcess = await TestProcess.start('dart', ['tooling-daemon']);
    final dtdUri = await _getDTDUri(dtdProcess);

    final fakeEditorExtension = await FakeEditorExtension.connect(dtdUri);
    addTearDown(fakeEditorExtension.shutdown);

    return TestHarness._(mcpClient, connection, fakeEditorExtension, dtdUri);
  }

  /// Starts an app debug session.
  Future<AppDebugSession> startDebugSession(
    String projectRoot,
    String appPath, {
    required bool isFlutter,
  }) async {
    var session = await AppDebugSession._start(
      projectRoot,
      appPath,
      isFlutter: isFlutter,
    );
    fakeEditorExtension.debugSessions.add(session);
    var root = rootForPath(projectRoot);
    var roots = (await mcpClient.handleListRoots(ListRootsRequest())).roots;
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

  /// Connects the MCP server to the dart tooling daemon at [dtdUri] using the
  /// "connectDartToolingDaemon" tool function.
  Future<void> connectToDtd() async {
    final tools = (await mcpServerConnection.listTools()).tools;

    final connectTool = tools.singleWhere(
      (t) => t.name == DartToolingDaemonSupport.connectTool.name,
    );

    final result = await callToolWithRetry(
      CallToolRequest(name: connectTool.name, arguments: {'uri': dtdUri}),
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
      if (!isFlutter) '--enable-vm-service',
      if (isFlutter) ...['-d', platform],
      appPath,
    ], workingDirectory: projectRoot);

    addTearDown(() async {
      if (isFlutter) {
        process.stdin.writeln('q');
      } else {
        unawaited(process.kill());
      }
      await process.shouldExit(0);
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
  final DartToolingDaemon dtd;
  int get nextId => ++_nextId;
  int _nextId = 0;

  FakeEditorExtension(this.dtd) {
    _registerService();
  }

  static Future<FakeEditorExtension> connect(String dtdUri) async {
    final dtd = await DartToolingDaemon.connect(Uri.parse(dtdUri));
    return FakeEditorExtension(dtd);
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

/// Starts up the [DartToolingMCPServer] and connects [client] to it.
///
/// Also handles the full intialization handshake between the client and
/// server.
Future<ServerConnection> _initializeMCPServer(
  MCPClient client,
  bool debugMode,
) async {
  ServerConnection connection;
  if (debugMode) {
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
    final mcpServer = DartToolingMCPServer(channel: serverChannel);
    addTearDown(mcpServer.shutdown);
    connection = client.connectServer(clientChannel);
  } else {
    connection = await client.connectStdioServer(await _compileMCPServer(), []);
  }

  final initializeResult = await connection.initialize(
    InitializeRequest(
      protocolVersion: protocolVersion,
      capabilities: client.capabilities,
      clientInfo: client.implementation,
    ),
  );
  expect(initializeResult.protocolVersion, protocolVersion);
  connection.notifyInitialized(InitializedNotification());
  return connection;
}

/// Creates a canoncical [Root] object for a given [projectPath].
Root rootForPath(String projectPath) =>
    Root(uri: Directory(projectPath).absolute.uri.toString());

const counterAppPath = 'test_fixtures/counter_app';
