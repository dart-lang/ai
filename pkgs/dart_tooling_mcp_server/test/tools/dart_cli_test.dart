// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_mcp/server.dart';
import 'package:dart_tooling_mcp_server/src/mixins/dash_cli.dart';
import 'package:dart_tooling_mcp_server/src/utils/constants.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../test_harness.dart';

void main() {
  late TestHarness testHarness;
  late TestProcessManager testProcessManager;
  late Root exampleFlutterAppRoot;
  late Root dartCliAppRoot;

  // TODO: Use setUpAll, currently this fails due to an apparent TestProcess
  // issue.
  setUp(() async {
    testHarness = await TestHarness.start(inProcess: true);
    testProcessManager =
        testHarness.serverConnectionPair.server!.processManager
            as TestProcessManager;

    final flutterExample = d.dir('flutter_example', [
      d.file('pubspec.yaml', '''
name: flutter_example
environment:
  sdk: ^3.0.0
dependencies:
  flutter:
    sdk: flutter
'''),
    ]);
    await flutterExample.create();

    exampleFlutterAppRoot = testHarness.rootForPath(flutterExample.io.path);
    dartCliAppRoot = testHarness.rootForPath(dartCliAppsPath);

    testHarness.mcpClient.addRoot(exampleFlutterAppRoot);
    await pumpEventQueue();
  });

  group('cli tools', () {
    late Tool dartFixTool;
    late Tool dartFormatTool;

    setUp(() async {
      final tools = (await testHarness.mcpServerConnection.listTools()).tools;
      dartFixTool = tools.singleWhere(
        (t) => t.name == DashCliSupport.dartFixTool.name,
      );
      dartFormatTool = tools.singleWhere(
        (t) => t.name == DashCliSupport.dartFormatTool.name,
      );
    });

    test('dart fix', () async {
      final request = CallToolRequest(
        name: dartFixTool.name,
        arguments: {
          ParameterNames.roots: [
            {ParameterNames.root: exampleFlutterAppRoot.uri},
          ],
        },
      );
      final result = await testHarness.callToolWithRetry(request);

      // Verify the command was sent to the process manager without error.
      expect(result.isError, isNot(true));
      expect(testProcessManager.commandsRan, [
        equalsCommand((
          command: ['dart', 'fix', '--apply'],
          workingDirectory: exampleFlutterAppRoot.path,
        )),
      ]);
    });

    test('dart format', () async {
      final request = CallToolRequest(
        name: dartFormatTool.name,
        arguments: {
          ParameterNames.roots: [
            {ParameterNames.root: exampleFlutterAppRoot.uri},
          ],
        },
      );
      final result = await testHarness.callToolWithRetry(request);

      // Verify the command was sent to the process manager without error.
      expect(result.isError, isNot(true));
      expect(testProcessManager.commandsRan, [
        equalsCommand((
          command: ['dart', 'format', '.'],
          workingDirectory: exampleFlutterAppRoot.path,
        )),
      ]);
    });

    test('dart format with paths', () async {
      final request = CallToolRequest(
        name: dartFormatTool.name,
        arguments: {
          ParameterNames.roots: [
            {
              ParameterNames.root: exampleFlutterAppRoot.uri,
              ParameterNames.paths: ['foo.dart', 'bar.dart'],
            },
          ],
        },
      );
      final result = await testHarness.callToolWithRetry(request);

      // Verify the command was sent to the process manager without error.
      expect(result.isError, isNot(true));
      expect(testProcessManager.commandsRan, [
        equalsCommand((
          command: ['dart', 'format', 'foo.dart', 'bar.dart'],
          workingDirectory: exampleFlutterAppRoot.path,
        )),
      ]);
    });

    test('flutter and dart package tests with paths', () async {
      testHarness.mcpClient.addRoot(dartCliAppRoot);
      await pumpEventQueue();
      final request = CallToolRequest(
        name: DashCliSupport.runTestsTool.name,
        arguments: {
          ParameterNames.roots: [
            {
              ParameterNames.root: exampleFlutterAppRoot.uri,
              ParameterNames.paths: ['foo_test.dart', 'bar_test.dart'],
            },
            {
              ParameterNames.root: dartCliAppRoot.uri,
              ParameterNames.paths: ['zip_test.dart'],
            },
          ],
        },
      );
      final result = await testHarness.callToolWithRetry(request);

      // Verify the command was sent to the process manager without error.
      expect(result.isError, isNot(true));
      expect(testProcessManager.commandsRan, [
        equalsCommand((
          command: ['flutter', 'test', 'foo_test.dart', 'bar_test.dart'],
          workingDirectory: exampleFlutterAppRoot.path,
        )),
        equalsCommand((
          command: ['dart', 'test', 'zip_test.dart'],
          workingDirectory: dartCliAppRoot.path,
        )),
      ]);
    });
  });
}
