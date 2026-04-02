// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp_server/src/mixins/analyzer.dart';
import 'package:dart_mcp_server/src/utils/names.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;
import 'package:unified_analytics/unified_analytics.dart';

import '../test_harness.dart';

void main() {
  group('analyze_files', () {
    late TestHarness testHarness;
    late FakeAnalytics analytics;
    late Tool analyzeTool;

    setUp(() async {
      testHarness = await TestHarness.start(inProcess: true);
      analytics =
          testHarness.serverConnectionPair.server!.analytics as FakeAnalytics;
      final tools = (await testHarness.mcpServerConnection.listTools()).tools;
      analyzeTool = tools.singleWhere(
        (t) => t.name == DartAnalyzerSupport.analyzeFilesTool.name,
      );
    });

    test('can apply quick fixes automatically', () async {
      final project = d.dir('project', [
        d.file('pubspec.yaml', '''
name: test_project
environment:
  sdk: '>=3.0.0 <4.0.0'
'''),
        d.file('analysis_options.yaml', '''
linter:
  rules:
    - unnecessary_new
'''),
        d.file('main.dart', '''
class A {}
void main() {
  final a = new A();
  print(a);
  final x = 'hello';
  print(x?.length);
}
'''),
      ]);
      await project.create();
      final projectRoot = testHarness.rootForPath(project.io.path);
      testHarness.mcpClient.addRoot(projectRoot);
      await pumpEventQueue();

      final analyzeRequest = CallToolRequest(
        name: analyzeTool.name,
        arguments: {
          ParameterNames.roots: [
            {ParameterNames.root: projectRoot.uri},
          ],
          ParameterNames.applyFixes: false,
        },
      );
      var result = await testHarness.callTool(analyzeRequest);
      final containsInvalidNullAwareOperator = contains(
        isA<TextContent>().having(
          (t) => t.text,
          'text',
          contains('invalid_null_aware_operator'),
        ),
      );
      final containsUnnecessaryNew = contains(
        isA<TextContent>().having(
          (t) => t.text,
          'text',
          contains('unnecessary_new'),
        ),
      );
      expect(result.content, containsInvalidNullAwareOperator);
      expect(result.content, containsUnnecessaryNew);
      expect(
        analytics.sentEvents.last.eventData,
        allOf(
          isNot(contains(AnalysisMetrics.applyFixesTimeMsKey)),
          containsPair(AnalysisMetrics.analyzerReadyTimeMsKey, isA<int>()),
          containsPair(AnalysisMetrics.didInitializeAnalysisServerKey, true),
        ),
      );

      // Actually apply the fixes now.
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

      // Verify the file has been fixed.
      final mainFile = File(p.join(project.io.path, 'main.dart'));
      final content = await mainFile.readAsString();
      expect(content, isNot(contains('new A()')));
      expect(content, contains('A()'));
      expect(content, contains('x.length'));
      expect(content, isNot(contains('x?.length')));

      // Verify that we don't report the fixed errors
      expect(result.content, isNot(containsInvalidNullAwareOperator));
      expect(result.content, isNot(containsUnnecessaryNew));
      expect(
        analytics.sentEvents.last.eventData,
        allOf(
          containsPair(AnalysisMetrics.applyFixesTimeMsKey, isA<int>()),
          containsPair(AnalysisMetrics.analyzerReadyTimeMsKey, isA<int>()),
          containsPair(AnalysisMetrics.didInitializeAnalysisServerKey, false),
        ),
      );

      // Finally, verify no errors are returned for future analysis.
      result = await testHarness.callToolWithRetry(analyzeRequest);
      expect(
        result.content,
        contains(isA<TextContent>().having((t) => t.text, 'text', 'No errors')),
      );

      expect(
        analytics.sentEvents.last.eventData,
        allOf(
          isNot(contains(AnalysisMetrics.applyFixesTimeMsKey)),
          containsPair(AnalysisMetrics.analyzerReadyTimeMsKey, isA<int>()),
          containsPair(AnalysisMetrics.didInitializeAnalysisServerKey, false),
        ),
      );
    });
  });
}
