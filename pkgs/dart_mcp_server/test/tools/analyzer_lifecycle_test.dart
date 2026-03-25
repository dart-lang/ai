// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp_server/src/mixins/analyzer.dart';
import 'package:dart_mcp_server/src/server.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../test_harness.dart';

void main() {
  late TestHarness testHarness;
  late DartMCPServer server;

  group('analyzer lifecycle', () {
    final originalTimeout = DartAnalyzerSupport.lspInactivityDuration;

    setUp(() async {
      testHarness = await TestHarness.start(inProcess: true);
      server = testHarness.serverConnectionPair.server!;
    });

    tearDown(() {
      DartAnalyzerSupport.lspInactivityDuration = originalTimeout;
    });

    test('lsp server starts on first tool call', () async {
      final example = d.dir('example', [
        d.file('main.dart', 'void main() => 1;'),
      ]);
      await example.create();
      final exampleRoot = testHarness.rootForPath(example.io.path);
      testHarness.mcpClient.addRoot(exampleRoot);

      // Give a chance for the server to start, but assert it has not.
      await pumpEventQueue();
      expect(server.liveAnalysisServer, isNull);
      expect(server.lspInitialization, isNull);

      final request = CallToolRequest(
        name: DartAnalyzerSupport.analyzeFilesTool.name,
      );
      final result = await testHarness.callToolWithRetry(request);
      expect(result.isError, isNot(true));
      expect(
        result.content.first,
        isA<TextContent>().having((t) => t.text, 'text', contains('No errors')),
      );
      expect(server.liveAnalysisServer, isNotNull);
    });

    test('auto-disconnects after inactivity', () async {
      DartAnalyzerSupport.lspInactivityDuration = const Duration(seconds: 0);

      final example = d.dir('example', [
        d.file('main.dart', 'void main() => 1;'),
      ]);
      await example.create();
      final exampleRoot = testHarness.rootForPath(example.io.path);
      testHarness.mcpClient.addRoot(exampleRoot);

      final request = CallToolRequest(
        name: DartAnalyzerSupport.analyzeFilesTool.name,
      );
      var result = await testHarness.callToolWithRetry(request);
      expect(result.isError, isNot(true));
      await pumpEventQueue();
      expect(server.liveAnalysisServer, isNull);

      // Check that we can call the tool again though.
      result = await testHarness.callToolWithRetry(request);
      expect(result.isError, isNot(true));
      expect(
        result.content.first,
        isA<TextContent>().having((t) => t.text, 'text', contains('No errors')),
      );
    });

    test('re-re-synchronizes roots after restart', () async {
      DartAnalyzerSupport.lspInactivityDuration = const Duration(seconds: 0);

      final example1 = d.dir('example1', [
        d.file('main.dart', 'void main() => 1 + "2";'),
      ]);
      final example2 = d.dir('example2', [
        d.file('other.dart', 'int x = "3";'),
      ]);
      await example1.create();
      await example2.create();

      final root1 = testHarness.rootForPath(example1.io.path);
      final root2 = testHarness.rootForPath(example2.io.path);

      testHarness.mcpClient.addRoot(root1);
      await pumpEventQueue();

      await testHarness.callToolWithRetry(
        CallToolRequest(name: DartAnalyzerSupport.analyzeFilesTool.name),
      );
      await pumpEventQueue();
      expect(server.liveAnalysisServer, isNull);

      testHarness.mcpClient.addRoot(root2);
      await pumpEventQueue();

      final result = await testHarness.callToolWithRetry(
        CallToolRequest(name: DartAnalyzerSupport.analyzeFilesTool.name),
      );
      expect(result.isError, isNot(true));
      final text = result.content
          .map((c) => (c as TextContent).text)
          .join('\n');
      expect(text, contains('# Diagnostics for root ${root1.uri}'));
      expect(text, contains('# Diagnostics for root ${root2.uri}'));
      expect(
        text,
        contains(
          "The argument type 'String' can't be assigned to the parameter type "
          "'num'.",
        ),
      );
      expect(
        text,
        contains(
          "A value of type 'String' can't be assigned to a variable of type "
          "'int'.",
        ),
      );
    });

    test('concurrent requests keep the server alive', () async {
      DartAnalyzerSupport.lspInactivityDuration = const Duration(seconds: 0);

      final example = d.dir('example', [
        d.file('main.dart', 'void main() => 1;'),
      ]);
      await example.create();
      testHarness.mcpClient.addRoot(testHarness.rootForPath(example.io.path));
      await pumpEventQueue();

      final c1 = Completer<CallToolResult>();
      final c2 = Completer<CallToolResult>();
      final serverReady = Completer<void>();
      final f1 = server.withAnalysisServer((_) {
        serverReady.complete();
        return c1.future;
      });
      final f2 = server.withAnalysisServer((_) => c2.future);
      await serverReady.future;
      await pumpEventQueue();
      expect(server.activeLspRequests, 2);

      c1.complete(CallToolResult(content: []));
      await f1;
      expect(server.activeLspRequests, 1);
      await pumpEventQueue();
      expect(server.liveAnalysisServer, isNotNull);

      c2.complete(CallToolResult(content: []));
      await f2;
      expect(server.activeLspRequests, 0);

      await pumpEventQueue();
      expect(server.liveAnalysisServer, isNull);
    });
  });
}
