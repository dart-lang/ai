// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_mcp/server.dart';
import 'package:dart_tooling_mcp_server/src/mixins/dart_cli.dart';
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
    late Tool dartPubTool;

    setUp(() async {
      final tools = (await testHarness.mcpServerConnection.listTools()).tools;
      dartFixTool = tools.singleWhere(
        (t) => t.name == DartCliSupport.dartFixTool.name,
      );
      dartFormatTool = tools.singleWhere(
        (t) => t.name == DartCliSupport.dartFormatTool.name,
      );
      dartPubTool = tools.singleWhere(
        (t) => t.name == DartCliSupport.dartPubTool.name,
      );
    });

    test('dart fix', () async {
      final request = CallToolRequest(
        name: dartFixTool.name,
        arguments: {
          'roots': [
            {'root': testRoot.uri},
          ],
        },
      );
      final result = await testHarness.callToolWithRetry(request);

      // Verify the command was sent to the process maanger without error.
      expect(result.isError, isNot(true));
      expect(testProcessManager.commandsRan, [
        ['dart', 'fix', '--apply'],
      ]);
    });

    test('dart format', () async {
      final request = CallToolRequest(
        name: dartFormatTool.name,
        arguments: {
          'roots': [
            {'root': testRoot.uri},
          ],
        },
      );
      final result = await testHarness.callToolWithRetry(request);

      // Verify the command was sent to the process maanger without error.
      expect(result.isError, isNot(true));
      expect(testProcessManager.commandsRan, [
        ['dart', 'format', '.'],
      ]);
    });

    test('dart format with paths', () async {
      final request = CallToolRequest(
        name: dartFormatTool.name,
        arguments: {
          'roots': [
            {
              'root': testRoot.uri,
              'paths': ['foo.dart', 'bar.dart'],
            },
          ],
        },
      );
      final result = await testHarness.callToolWithRetry(request);

      // Verify the command was sent to the process maanger without error.
      expect(result.isError, isNot(true));
      expect(testProcessManager.commandsRan, [
        ['dart', 'format', 'foo.dart', 'bar.dart'],
      ]);
    });

    group('dart pub', () {
      test('add', () async {
        final request = CallToolRequest(
          name: dartPubTool.name,
          arguments: {
            'command': 'add',
            'packageName': 'foo',
            'roots': [
              {'root': testRoot.uri},
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
            'command': 'remove',
            'packageName': 'foo',
            'roots': [
              {'root': testRoot.uri},
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
            'command': 'get',
            'roots': [
              {'root': testRoot.uri},
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
            'command': 'upgrade',
            'roots': [
              {'root': testRoot.uri},
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
            arguments: {'command': 'publish'},
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
              arguments: {'command': command.name},
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

        test('for missing roots', () async {
          final request = CallToolRequest(
            name: dartPubTool.name,
            arguments: {'command': 'get'},
          );
          final result = await testHarness.callToolWithRetry(
            request,
            expectError: true,
          );

          expect(
            (result.content.single as TextContent).text,
            'Missing required argument `roots`.',
          );
          expect(testProcessManager.commandsRan, isEmpty);
        });
      });
    });
  });
}
