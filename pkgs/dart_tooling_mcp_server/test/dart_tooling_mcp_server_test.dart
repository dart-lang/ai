// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_mcp/server.dart';
import 'package:test/test.dart';

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

    await testHarness.startDebugSession(counterAppPath, 'lib/main.dart',
        isFlutter: true);

    final tools = (await testHarness.mcpServerConnection.listTools()).tools;
    final screenshotTool = tools.singleWhere(
      (t) => t.name == 'take_screenshot',
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
}
