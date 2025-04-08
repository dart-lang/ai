// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_mcp/server.dart';
import 'package:dart_tooling_mcp_server/src/mixins/analyzer.dart';
import 'package:dart_tooling_mcp_server/src/mixins/dtd.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import 'test_harness.dart';

void main() {
  late TestHarness testHarness;

  // TODO: Use setUpAll, currently this fails due to an apparent TestProcess
  // issue.
  setUp(() async {
    testHarness = await TestHarness.start();
    await testHarness.connectToDtd();
  });

  test('can take a screenshot', () async {
    final tools = (await testHarness.mcpServerConnection.listTools()).tools;
    final screenshotTool = tools.singleWhere(
      (t) => t.name == DartToolingDaemonSupport.screenshotTool.name,
    );
    final screenshotResult = await testHarness.callToolWithRetry(
      CallToolRequest(name: screenshotTool.name),
    );
    expect(
      screenshotResult.content.single,
      {
        'data': anything,
        'mimeType': 'image/png',
        'type': ImageContent.expectedType
      },
    );
  });

  group('analysis', () {
    late Tool analyzeTool;

    setUp(() async {
      final tools = (await testHarness.mcpServerConnection.listTools()).tools;
      analyzeTool = tools.singleWhere(
          (t) => t.name == DartAnalyzerSupport.analyzeFilesTool.name);
    });

    test('can analyze a project', () async {
      final request = CallToolRequest(
        name: analyzeTool.name,
        arguments: {
          'roots': [
            {
              'root': Uri.base.resolve(counterAppPath).toString(),
              'paths': ['lib/main.dart']
            }
          ]
        },
      );
      final result = await testHarness.callToolWithRetry(request);
      expect(result.isError, isNot(true));
      expect(result.content, isEmpty);
    });

    test('can handle project changes', () async {
      final example =
          d.dir('example', [d.file('main.dart', 'void main() => 1 + "2";')]);
      await example.create();
      final exampeRoot = Root(uri: example.io.absolute.uri.toString());
      testHarness.mcpClient.addRoot(exampeRoot);

      // Allow the notification to propagate, and the server to ask for the new
      // list of roots.
      await pumpEventQueue();

      final request = CallToolRequest(
        name: analyzeTool.name,
        arguments: {
          'roots': [
            {
              'root': exampeRoot.uri,
              'paths': ['main.dart']
            }
          ]
        },
      );
      var result = await testHarness.callToolWithRetry(request);
      expect(result.isError, isNot(true));
      expect(result.content, [
        TextContent(
            text: "Error: The argument type 'String' can't be assigned to the "
                "parameter type 'num'. "),
      ]);

      // Change the file to fix the error
      await d.dir(
          'example', [d.file('main.dart', 'void main() => 1 + 2;')]).create();
      // Wait for the file watcher to pick up the change, the default delay for
      // a polling watcher is one second.
      await Future<void>.delayed(const Duration(seconds: 1));

      result = await testHarness.callToolWithRetry(request);
      expect(result.isError, isNot(true));
      expect(result.content, isEmpty);
    });
  });
}
