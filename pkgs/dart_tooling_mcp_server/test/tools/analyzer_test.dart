// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:dart_tooling_mcp_server/src/mixins/analyzer.dart';
import 'package:dart_tooling_mcp_server/src/utils/constants.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../test_harness.dart';

void main() {
  late TestHarness testHarness;

  // TODO: Use setUpAll, currently this fails due to an apparent TestProcess
  // issue.
  setUp(() async {
    testHarness = await TestHarness.start();
  });

  group('analyzer tools', () {
    late Tool analyzeTool;

    setUp(() async {
      final tools = (await testHarness.mcpServerConnection.listTools()).tools;
      analyzeTool = tools.singleWhere(
        (t) => t.name == DartAnalyzerSupport.analyzeFilesTool.name,
      );
    });

    test('can analyze a project', () async {
      final counterAppRoot = testHarness.rootForPath(counterAppPath);
      testHarness.mcpClient.addRoot(counterAppRoot);
      // Allow the notification to propagate, and the server to ask for the new
      // list of roots.
      await pumpEventQueue();

      final request = CallToolRequest(name: analyzeTool.name);
      final result = await testHarness.callToolWithRetry(request);
      expect(result.isError, isNot(true));
      expect(
        result.content.single,
        isA<TextContent>().having((t) => t.text, 'text', 'No errors'),
      );
    });

    test('can handle project changes', () async {
      final example = d.dir('example', [
        d.file('main.dart', 'void main() => 1 + "2";'),
      ]);
      await example.create();
      final exampleRoot = testHarness.rootForPath(example.io.path);
      testHarness.mcpClient.addRoot(exampleRoot);

      // Allow the notification to propagate, and the server to ask for the new
      // list of roots.
      await pumpEventQueue();

      final request = CallToolRequest(name: analyzeTool.name);
      var result = await testHarness.callToolWithRetry(request);
      expect(result.isError, isNot(true));
      expect(result.content, [
        isA<TextContent>().having(
          (t) => t.text,
          'text',
          contains(
            "The argument type 'String' can't be assigned to the parameter "
            "type 'num'.",
          ),
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
      expect(
        result.content.single,
        isA<TextContent>().having((t) => t.text, 'text', 'No errors'),
      );
    });

    test('can look up symbols in a workspace', () async {
      final currentRoot = testHarness.rootForPath(Directory.current.path);
      testHarness.mcpClient.addRoot(currentRoot);
      await pumpEventQueue();

      final result = await testHarness.callToolWithRetry(
        CallToolRequest(
          name: DartAnalyzerSupport.resolveWorkspaceSymbolTool.name,
          arguments: {ParameterNames.query: 'DartAnalyzerSupport'},
        ),
      );
      expect(result.isError, isNot(true));

      expect(
        result.content.single,
        isA<TextContent>().having(
          (t) => t.text,
          'text',
          contains('analyzer.dart'),
        ),
      );
    });

    test('can get signature help', () async {
      final counterAppRoot = testHarness.rootForPath(counterAppPath);
      testHarness.mcpClient.addRoot(counterAppRoot);
      await pumpEventQueue();

      final result = await testHarness.callToolWithRetry(
        CallToolRequest(
          name: DartAnalyzerSupport.signatureHelpTool.name,
          arguments: {
            ParameterNames.uri: p.join(counterAppRoot.uri, 'lib', 'main.dart'),
            ParameterNames.line: 16,
            ParameterNames.column: 15,
          },
        ),
      );
      expect(result.isError, isNot(true));

      expect(
        result.content.single,
        isA<TextContent>().having(
          (t) => t.text,
          'text',
          allOf(
            contains('Creates a MaterialApp'), // From the doc comment
            contains('MaterialApp({Key? key,'), // The actual signature
            contains('"label":"Key? key'), // Specific label for the key param
          ),
        ),
      );
    });

    test('can get hover information', () async {
      final counterAppRoot = testHarness.rootForPath(counterAppPath);
      testHarness.mcpClient.addRoot(counterAppRoot);
      await pumpEventQueue();

      final result = await testHarness.callToolWithRetry(
        CallToolRequest(
          name: DartAnalyzerSupport.hoverTool.name,
          arguments: {
            ParameterNames.uri: p.join(counterAppRoot.uri, 'lib', 'main.dart'),
            ParameterNames.line: 15,
            ParameterNames.column: 15,
          },
        ),
      );
      expect(result.isError, isNot(true));

      expect(
        result.content.single,
        isA<TextContent>().having(
          (t) => t.text,
          'text',
          allOf(
            /// The signature of the material app constructor.
            contains('MaterialApp({'),
            contains('Key? key,'),
          ),
        ),
      );
    });

    test('cannot analyze without roots set', () async {
      final result = await testHarness.callToolWithRetry(
        CallToolRequest(name: DartAnalyzerSupport.analyzeFilesTool.name),
        expectError: true,
      );
      expect(
        result.content.single,
        isA<TextContent>().having(
          (t) => t.text,
          'text',
          contains('No roots set'),
        ),
      );
    });

    test('cannot look up symbols without roots set', () async {
      final result = await testHarness.callToolWithRetry(
        CallToolRequest(
          name: DartAnalyzerSupport.resolveWorkspaceSymbolTool.name,
          arguments: {ParameterNames.query: 'DartAnalyzerSupport'},
        ),
        expectError: true,
      );
      expect(
        result.content.single,
        isA<TextContent>().having(
          (t) => t.text,
          'text',
          contains('No roots set'),
        ),
      );
    });

    test('cannot get hover information without roots set', () async {
      final result = await testHarness.callToolWithRetry(
        CallToolRequest(
          name: DartAnalyzerSupport.hoverTool.name,
          arguments: {
            ParameterNames.uri: 'file:///any/file.dart',
            ParameterNames.line: 0,
            ParameterNames.column: 0,
          },
        ),
        expectError: true,
      );
      expect(
        result.content.single,
        isA<TextContent>().having(
          (t) => t.text,
          'text',
          contains('No roots set'),
        ),
      );
    });
  });
}
