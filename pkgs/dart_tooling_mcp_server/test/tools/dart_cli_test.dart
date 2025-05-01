// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_mcp/server.dart';
import 'package:dart_tooling_mcp_server/src/mixins/dart_cli.dart';
import 'package:dart_tooling_mcp_server/src/utils/constants.dart';
import 'package:test/test.dart';

import '../test_harness.dart';

void main() {
  late TestHarness testHarness;
  late TestProcessManager testProcessManager;

  // This root is arbitrary for these tests since we are not actually running
  // the CLI commands, but rather sending them through the
  // [TestProcessManager] wrapper.
  final testRoot = rootForPath(counterAppPath);

  // TODO: Use setUpAll, currently this fails due to an apparent TestProcess
  // issue.
  setUp(() async {
    testHarness = await TestHarness.start(inProcess: true);
    testProcessManager =
        testHarness.serverConnectionPair.server!.processManager
            as TestProcessManager;

    testHarness.mcpClient.addRoot(testRoot);
    await pumpEventQueue();
  });

  group('dart cli tools', () {
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

    test('dart fix', () async {
      final request = CallToolRequest(
        name: dartFixTool.name,
        arguments: {
          ParameterNames.roots: [
            {ParameterNames.root: testRoot.uri},
          ],
        },
      );
      final result = await testHarness.callToolWithRetry(request);

      // Verify the command was sent to the process manager without error.
      expect(result.isError, isNot(true));
      expect(testProcessManager.commandsRan, [
        ['dart', 'fix', '--apply'],
      ]);
    });

    test('dart format', () async {
      final request = CallToolRequest(
        name: dartFormatTool.name,
        arguments: {
          ParameterNames.roots: [
            {ParameterNames.root: testRoot.uri},
          ],
        },
      );
      final result = await testHarness.callToolWithRetry(request);

      // Verify the command was sent to the process manager without error.
      expect(result.isError, isNot(true));
      expect(testProcessManager.commandsRan, [
        ['dart', 'format', '.'],
      ]);
    });

    test('dart format with paths', () async {
      final request = CallToolRequest(
        name: dartFormatTool.name,
        arguments: {
          ParameterNames.roots: [
            {
              ParameterNames.root: testRoot.uri,
              ParameterNames.paths: ['foo.dart', 'bar.dart'],
            },
          ],
        },
      );
      final result = await testHarness.callToolWithRetry(request);

      // Verify the command was sent to the process manager without error.
      expect(result.isError, isNot(true));
      expect(testProcessManager.commandsRan, [
        ['dart', 'format', 'foo.dart', 'bar.dart'],
      ]);
    });
  });
}
