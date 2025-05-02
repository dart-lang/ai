// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_mcp/server.dart';
import 'package:dart_tooling_mcp_server/src/mixins/pub.dart';
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

  late Tool dartPubTool;

  // TODO: Use setUpAll, currently this fails due to an apparent TestProcess
  // issue.
  setUp(() async {
    testHarness = await TestHarness.start(inProcess: true);
    testProcessManager =
        testHarness.serverConnectionPair.server!.processManager
            as TestProcessManager;

    testHarness.mcpClient.addRoot(testRoot);
    await pumpEventQueue();

    final tools = (await testHarness.mcpServerConnection.listTools()).tools;
    dartPubTool = tools.singleWhere((t) => t.name == PubSupport.pubTool.name);
  });

  group('pub tools', () {
    test('add', () async {
      final request = CallToolRequest(
        name: dartPubTool.name,
        arguments: {
          ParameterNames.command: 'add',
          ParameterNames.packageName: 'foo',
          ParameterNames.roots: [
            {ParameterNames.root: testRoot.uri},
          ],
        },
      );
      final result = await testHarness.callToolWithRetry(request);

      // Verify the command was sent to the process maanger without error.
      expect(result.isError, isNot(true));
      expect(testProcessManager.commandsRan, [
        ['dart', 'pub', 'add', 'foo'],
      ]);
    });

    test('remove', () async {
      final request = CallToolRequest(
        name: dartPubTool.name,
        arguments: {
          ParameterNames.command: 'remove',
          ParameterNames.packageName: 'foo',
          ParameterNames.roots: [
            {ParameterNames.root: testRoot.uri},
          ],
        },
      );
      final result = await testHarness.callToolWithRetry(request);

      // Verify the command was sent to the process maanger without error.
      expect(result.isError, isNot(true));
      expect(testProcessManager.commandsRan, [
        ['dart', 'pub', 'remove', 'foo'],
      ]);
    });

    test('get', () async {
      final request = CallToolRequest(
        name: dartPubTool.name,
        arguments: {
          ParameterNames.command: 'get',
          ParameterNames.roots: [
            {ParameterNames.root: testRoot.uri},
          ],
        },
      );
      final result = await testHarness.callToolWithRetry(request);

      // Verify the command was sent to the process maanger without error.
      expect(result.isError, isNot(true));
      expect(testProcessManager.commandsRan, [
        ['dart', 'pub', 'get'],
      ]);
    });

    test('upgrade', () async {
      final request = CallToolRequest(
        name: dartPubTool.name,
        arguments: {
          ParameterNames.command: 'upgrade',
          ParameterNames.roots: [
            {ParameterNames.root: testRoot.uri},
          ],
        },
      );
      final result = await testHarness.callToolWithRetry(request);

      // Verify the command was sent to the process maanger without error.
      expect(result.isError, isNot(true));
      expect(testProcessManager.commandsRan, [
        ['dart', 'pub', 'upgrade'],
      ]);
    });

    group('returns error', () {
      test('for missing command', () async {
        final request = CallToolRequest(name: dartPubTool.name);
        final result = await testHarness.callToolWithRetry(
          request,
          expectError: true,
        );

        expect(
          (result.content.single as TextContent).text,
          'Missing required argument `command`.',
        );
        expect(testProcessManager.commandsRan, isEmpty);
      });

      test('for unsupported command', () async {
        final request = CallToolRequest(
          name: dartPubTool.name,
          arguments: {ParameterNames.command: 'publish'},
        );
        final result = await testHarness.callToolWithRetry(
          request,
          expectError: true,
        );

        expect(
          (result.content.single as TextContent).text,
          contains('Unsupported pub command `publish`.'),
        );
        expect(testProcessManager.commandsRan, isEmpty);
      });

      for (final command in SupportedPubCommand.values.where(
        (c) => c.requiresPackageName,
      )) {
        test('for missing package name: $command', () async {
          final request = CallToolRequest(
            name: dartPubTool.name,
            arguments: {ParameterNames.command: command.name},
          );
          final result = await testHarness.callToolWithRetry(
            request,
            expectError: true,
          );

          expect(
            (result.content.single as TextContent).text,
            'Missing required argument `packageName` for the '
            '`${command.name}` command.',
          );
          expect(testProcessManager.commandsRan, isEmpty);
        });
      }
    });
  });
}
