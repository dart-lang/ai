// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:devtools_shared/devtools_shared.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;
import 'package:test_process/test_process.dart';

class TestHarness {
  final TestProcess flutterProcess;
  final DartToolingMCPClient mcpClient;
  final ServerConnection mcpServerConnection;
  final String dtdUri;

  TestHarness._(
    this.flutterProcess,
    this.mcpClient,
    this.mcpServerConnection,
    this.dtdUri,
  ) {
    addTearDown(mcpClient.shutdown);
  }

  /// Starts a flutter process as well as an MCP client and server.
  ///
  /// Handles the initialization handshake between the MCP client and server as
  /// well.
  static Future<TestHarness> start() async {
    final flutterProcess = await TestProcess.start(
      // TODO: Get flutter SDK location from somewhere.
      'flutter',
      ['run', '-d', 'chrome'],
      workingDirectory: 'test_fixtures/counter_app',
    );
    final devtoolsServerUriCompleter = Completer<Uri>();
    var listener = flutterProcess.stdoutStream().listen((line) {
      const devtoolsLineStart =
          'The Flutter DevTools debugger and profiler on Chrome is available';
      if (line.startsWith(devtoolsLineStart)) {
        var uri = Uri.parse(line.substring(line.indexOf('http')));
        devtoolsServerUriCompleter.complete(uri.replace(query: ''));
      }
    });

    addTearDown(() async {
      flutterProcess.stdin.writeln('q');
      await flutterProcess.shouldExit(0);
    });

    final devtoolsUri = await devtoolsServerUriCompleter.future;
    await listener.cancel();

    final dtdUri =
        (jsonDecode(
                  (await http.get(
                    devtoolsUri.resolve(DtdApi.apiGetDtdUri),
                  )).body,
                )
                as Map<String, Object?>)['dtdUri']
            as String;

    final mcpClient = DartToolingMCPClient();
    final connection = await mcpClient.connectStdioServer(
      'dart tooling mcp server',
      await _compileMCPServer(),
      [],
    );

    final initializeResult = await connection.initialize(
      InitializeRequest(
        protocolVersion: protocolVersion,
        capabilities: mcpClient.capabilities,
        clientInfo: mcpClient.implementation,
      ),
    );
    expect(initializeResult.protocolVersion, protocolVersion);
    connection.notifyInitialized(InitializedNotification());

    return TestHarness._(flutterProcess, mcpClient, connection, dtdUri);
  }

  /// Connects the MCP server to the dart tooling daemon at [dtdUri] using the
  /// "connectDartToolingDaemon" tool function.
  Future<void> connectToDtd() async {
    final tools = (await mcpServerConnection.listTools()).tools;

    final connectTool = tools.singleWhere(
      (t) => t.name == 'connectDartToolingDaemon',
    );

    final result = await callToolWithRetry(
      CallToolRequest(name: connectTool.name, arguments: {'uri': dtdUri}),
    );
    expect(result.isError, isNot(true), reason: result.content.join('\n'));
  }

  /// Sends [request] to [mcpServerConnection], retrying 5 times.
  ///
  /// Some methods will fail if the DTD connection is not yet ready.
  Future<CallToolResult> callToolWithRetry(CallToolRequest request) async {
    final maxTries = 10;
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

final class DartToolingMCPClient extends MCPClient {
  DartToolingMCPClient()
    : super(
        ClientImplementation(
          name: 'test client for the dart tooling mcp server',
          version: '0.1.0',
        ),
      );
}

/// Compiles the dart tooling mcp server to AOT and returns the location.
Future<String> _compileMCPServer() async {
  final filePath = d.path('main.exe');
  var result = await TestProcess.start(Platform.executable, [
    'compile',
    'exe',
    'bin/main.dart',
    '-o',
    filePath,
  ]);
  await result.shouldExit(0);
  return filePath;
}
