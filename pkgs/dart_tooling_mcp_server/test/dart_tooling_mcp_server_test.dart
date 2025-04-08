// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_mcp/server.dart';
import 'package:dart_tooling_mcp_server/src/mixins/analyzer.dart';
import 'package:dart_tooling_mcp_server/src/mixins/dtd.dart';
import 'package:test/test.dart';

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

  test('can analyze a project', () async {
    final tools = (await testHarness.mcpServerConnection.listTools()).tools;
    final analyzeTool = tools.singleWhere(
        (t) => t.name == DartAnalyzerSupport.analyzeFilesTool.name);
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
    expect(result.isError, false);
    expect(result.content, isEmpty);
  });
}
