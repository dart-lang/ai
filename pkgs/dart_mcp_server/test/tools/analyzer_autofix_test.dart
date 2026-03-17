// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp_server/src/mixins/analyzer.dart';
import 'package:dart_mcp_server/src/utils/names.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../test_harness.dart';

void main() {
  late TestHarness testHarness;

  setUp(() async {
    testHarness = await TestHarness.start();
  });

  group('analyzer autoFix', () {
    late Tool analyzeTool;

    setUp(() async {
      final tools = (await testHarness.mcpServerConnection.listTools()).tools;
      analyzeTool = tools.singleWhere(
        (t) => t.name == DartAnalyzerSupport.analyzeFilesTool.name,
      );
    });

    test(
      'can apply quick fixes automatically',
      () async {
        // Create a project with a fixable error.
        // Unnecessary null-aware operator is a good candidate.
        final project = d.dir('project', [
          d.file('pubspec.yaml', '''
name: test_project
environment:
  sdk: '>=3.0.0 <4.0.0'
'''),
          d.file('main.dart', '''
void main() {
  final x = 'hello';
  print(x?.length);
}
'''),
        ]);
        await project.create();
        final projectRoot = testHarness.rootForPath(project.io.path);
        testHarness.mcpClient.addRoot(projectRoot);

        // Allow the notification to propagate.
        await pumpEventQueue();

        // First, verify the error exists without autoFix.
        final noFixRequest = CallToolRequest(
          name: analyzeTool.name,
          arguments: {
            ParameterNames.roots: [
              {ParameterNames.root: projectRoot.uri},
            ],
            ParameterNames.applyFixes: false,
          },
        );
        var result = await testHarness.callToolWithRetry(noFixRequest);
        final containsLint = contains(
          isA<TextContent>().having(
            (t) => t.text,
            'text',
            contains('invalid_null_aware_operator'),
          ),
        );
        expect(result.isError, isNot(true));
        expect(result.content, containsLint);

        // Now, call with autoFix: true.
        final fixRequest = CallToolRequest(
          name: analyzeTool.name,
          arguments: {
            ParameterNames.roots: [
              {ParameterNames.root: projectRoot.uri},
            ],
            ParameterNames.applyFixes: true,
          },
        );
        result = await testHarness.callToolWithRetry(fixRequest);
        expect(result.isError, isNot(true));
        expect(
          result.content,
          contains(
            isA<TextContent>().having(
              (t) => t.text,
              'text',
              'Applied quick fixes',
            ),
          ),
        );
        expect(result.content, isNot(containsLint));

        // Verify the file has been fixed.
        final mainFile = File(p.join(project.io.path, 'main.dart'));
        final content = await mainFile.readAsString();
        expect(content, contains('x.length'));
        expect(content, isNot(contains('x?.length')));

        // Finally, verify no errors are returned now.
        result = await testHarness.callToolWithRetry(noFixRequest);
        expect(result.isError, isNot(true));
        expect(
          result.content,
          contains(
            isA<TextContent>().having((t) => t.text, 'text', 'No errors'),
          ),
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
