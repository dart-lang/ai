// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:dart_tooling_mcp_server/src/mixins/analyzer.dart';
import 'package:dart_tooling_mcp_server/src/mixins/dart_cli.dart';
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
  });

  test('can take a screenshot', () async {
    await testHarness.connectToDtd();

    await testHarness.startDebugSession(
      counterAppPath,
      'lib/main.dart',
      isFlutter: true,
    );

    final tools = (await testHarness.mcpServerConnection.listTools()).tools;
    final screenshotTool = tools.singleWhere(
      (t) => t.name == DartToolingDaemonSupport.screenshotTool.name,
    );
    final screenshotResult = await testHarness.callToolWithRetry(
      CallToolRequest(name: screenshotTool.name),
    );
    expect(screenshotResult.content.single, {
      'data': anything,
      'mimeType': 'image/png',
      'type': ImageContent.expectedType,
    });
  });

  test('can perform a hot reload', () async {
    await testHarness.connectToDtd();

    await testHarness.startDebugSession(
      counterAppPath,
      'lib/main.dart',
      isFlutter: true,
    );

    final tools = (await testHarness.mcpServerConnection.listTools()).tools;
    final hotReloadTool = tools.singleWhere(
      (t) => t.name == DartToolingDaemonSupport.hotReloadTool.name,
    );
    final hotReloadResult = await testHarness.callToolWithRetry(
      CallToolRequest(name: hotReloadTool.name),
    );

    expect(hotReloadResult.isError, isNot(true));
    expect(hotReloadResult.content, [
      TextContent(text: 'Hot reload succeeded.'),
    ]);
  });

  group('analysis', () {
    late Tool analyzeTool;

    setUp(() async {
      final tools = (await testHarness.mcpServerConnection.listTools()).tools;
      analyzeTool = tools.singleWhere(
        (t) => t.name == DartAnalyzerSupport.analyzeFilesTool.name,
      );
    });

    test('can analyze a project', () async {
      final counterAppRoot = rootForPath(counterAppPath);
      testHarness.mcpClient.addRoot(counterAppRoot);
      // Allow the notification to propagate, and the server to ask for the new
      // list of roots.
      await pumpEventQueue();

      final request = CallToolRequest(
        name: analyzeTool.name,
        arguments: {
          'roots': [
            {
              'root': counterAppRoot.uri,
              'paths': ['lib/main.dart'],
            },
          ],
        },
      );
      final result = await testHarness.callToolWithRetry(request);
      expect(result.isError, isNot(true));
      expect(result.content, isEmpty);
    });

    test('can handle project changes', () async {
      final example = d.dir('example', [
        d.file('main.dart', 'void main() => 1 + "2";'),
      ]);
      await example.create();
      final exampleRoot = rootForPath(example.io.path);
      testHarness.mcpClient.addRoot(exampleRoot);

      // Allow the notification to propagate, and the server to ask for the new
      // list of roots.
      await pumpEventQueue();

      final request = CallToolRequest(
        name: analyzeTool.name,
        arguments: {
          'roots': [
            {
              'root': exampleRoot.uri,
              'paths': ['main.dart'],
            },
          ],
        },
      );
      var result = await testHarness.callToolWithRetry(request);
      expect(result.isError, isNot(true));
      expect(result.content, [
        TextContent(
          text:
              "Error: The argument type 'String' can't be assigned to the "
              "parameter type 'num'. ",
        ),
      ]);

      // Change the file to fix the error
      await d.dir('example', [
        d.file('main.dart', 'void main() => 1 + 2;'),
      ]).create();
      // Wait for the file watcher to pick up the change, the default delay for
      // a polling watcher is one second.
      await Future<void>.delayed(const Duration(seconds: 1));

      result = await testHarness.callToolWithRetry(request);
      expect(result.isError, isNot(true));
      expect(result.content, isEmpty);
    });
  });

  group('dart cli', () {
    late Tool dartFixTool;
    late Tool dartFormatTool;

    setUp(() async {
      final tools = (await testHarness.mcpServerConnection.listTools()).tools;
      dartFixTool = tools.singleWhere(
        (t) => t.name == DartCliSupport.dartFixTool.name,
      );
      dartFormatTool = tools.singleWhere(
        (t) => t.name == DartCliSupport.dartFormatTool.name,
      );
    });

    test('can run dart fix', () async {
      final fixExample = d.dir('fix_example', [
        d.file('main.dart', 'void main() { print("hello"); }'),
      ]);
      await fixExample.create();
      final fixExampleRoot = rootForPath(fixExample.io.path);
      testHarness.mcpClient.addRoot(fixExampleRoot);
      await pumpEventQueue();

      final request = CallToolRequest(
        name: dartFixTool.name,
        arguments: {
          'roots': [
            {'root': fixExampleRoot.uri},
          ],
        },
      );
      final result = await testHarness.callToolWithRetry(request);
      expect(result.isError, isNot(true));
      expect(
        (result.content.single as TextContent).text,
        contains('dart fix in ${fixExample.io.path}'),
      );
      expect(
        (result.content.single as TextContent).text,
        contains('Applied 1 fix'),
      );

      // Check that the file was modified
      final fixedContent =
          File(d.path('fix_example/main.dart')).readAsStringSync();
      expect(fixedContent, 'void main() {\n  print("hello");\n}\n');
    });

    test('can run dart format', () async {
      final formatExample = d.dir('format_example', [
        d.file('main.dart', 'void main() {print("hello");}'),
      ]);
      await formatExample.create();
      final formatExampleRoot = rootForPath(formatExample.io.path);
      testHarness.mcpClient.addRoot(formatExampleRoot);
      await pumpEventQueue();

      final request = CallToolRequest(
        name: dartFormatTool.name,
        arguments: {
          'roots': [
            {'root': formatExampleRoot.uri},
          ],
        },
      );
      final result = await testHarness.callToolWithRetry(request);
      expect(result.isError, isNot(true));
      expect(
        (result.content.single as TextContent).text,
        contains('dart format in ${formatExample.io.path}'),
      );
      expect(
        (result.content.single as TextContent).text,
        contains('Formatted 1 file'),
      );

      // Check that the file was modified
      final formattedContent =
          File(d.path('format_example/main.dart')).readAsStringSync();
      expect(formattedContent, 'void main() {\n  print("hello");\n}\n');
    });
  });
}
