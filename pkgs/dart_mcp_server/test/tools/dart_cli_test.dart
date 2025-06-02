// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp_server/src/mixins/dash_cli.dart';
import 'package:dart_mcp_server/src/utils/constants.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../test_harness.dart';

void main() {
  late TestHarness testHarness;
  late TestProcessManager testProcessManager;
  late Root exampleFlutterAppRoot;
  late Root dartCliAppRoot;
  final dartExecutableName = 'dart${Platform.isWindows ? '.exe' : ''}';
  final flutterExecutableName = 'flutter${Platform.isWindows ? '.bat' : ''}';

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

    await pumpEventQueue();
  });

  group('cli tools', () {
    late Tool dartFixTool;
    late Tool dartFormatTool;
    late Tool createProjectTool;

    setUp(() async {
      final tools = (await testHarness.mcpServerConnection.listTools()).tools;
      dartFixTool = tools.singleWhere(
        (t) => t.name == DashCliSupport.dartFixTool.name,
      );
      dartFormatTool = tools.singleWhere(
        (t) => t.name == DashCliSupport.dartFormatTool.name,
      );
      createProjectTool = tools.singleWhere(
        (t) => t.name == DashCliSupport.createProjectTool.name,
      );
    });

    test('dart fix', () async {
      testHarness.mcpClient.addRoot(exampleFlutterAppRoot);
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
          command: [endsWith(dartExecutableName), 'fix', '--apply'],
          workingDirectory: exampleFlutterAppRoot.path,
        )),
      ]);
    });

    test('dart format', () async {
      testHarness.mcpClient.addRoot(exampleFlutterAppRoot);
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
          command: [endsWith(dartExecutableName), 'format', '.'],
          workingDirectory: exampleFlutterAppRoot.path,
        )),
      ]);
    });

    test('dart format with paths', () async {
      testHarness.mcpClient.addRoot(exampleFlutterAppRoot);
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
          command: [
            endsWith(dartExecutableName),
            'format',
            'foo.dart',
            'bar.dart',
          ],
          workingDirectory: exampleFlutterAppRoot.path,
        )),
      ]);
    });

    test('flutter and dart package tests with paths', () async {
      testHarness.mcpClient.addRoot(dartCliAppRoot);
      testHarness.mcpClient.addRoot(exampleFlutterAppRoot);
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
          command: [
            endsWith(flutterExecutableName),
            'test',
            'foo_test.dart',
            'bar_test.dart',
          ],
          workingDirectory: exampleFlutterAppRoot.path,
        )),
        equalsCommand((
          command: [endsWith(dartExecutableName), 'test', 'zip_test.dart'],
          workingDirectory: dartCliAppRoot.path,
        )),
      ]);
    });

    group('create', () {
      test('creates a Dart project', () async {
        testHarness.mcpClient.addRoot(dartCliAppRoot);
        final request = CallToolRequest(
          name: createProjectTool.name,
          arguments: {
            ParameterNames.root: dartCliAppRoot.uri,
            ParameterNames.directory: 'new_app',
            ParameterNames.projectType: 'dart',
            ParameterNames.template: 'cli',
          },
        );
        await testHarness.callToolWithRetry(request);

        expect(testProcessManager.commandsRan, [
          equalsCommand((
            command: [
              endsWith(dartExecutableName),
              'create',
              '--template',
              'cli',
              'new_app',
            ],
            workingDirectory: dartCliAppRoot.path,
          )),
        ]);
      });

      test('creates a Flutter project', () async {
        testHarness.mcpClient.addRoot(exampleFlutterAppRoot);
        final request = CallToolRequest(
          name: createProjectTool.name,
          arguments: {
            ParameterNames.root: exampleFlutterAppRoot.uri,
            ParameterNames.directory: 'new_app',
            ParameterNames.projectType: 'flutter',
            ParameterNames.template: 'app',
          },
        );
        await testHarness.callToolWithRetry(request);

        expect(testProcessManager.commandsRan, [
          equalsCommand((
            command: [
              endsWith(flutterExecutableName),
              'create',
              '--template',
              'app',
              '--empty',
              'new_app',
            ],
            workingDirectory: exampleFlutterAppRoot.path,
          )),
        ]);
      });

      test('creates a non-empty Flutter project', () async {
        testHarness.mcpClient.addRoot(exampleFlutterAppRoot);
        final request = CallToolRequest(
          name: createProjectTool.name,
          arguments: {
            ParameterNames.root: exampleFlutterAppRoot.uri,
            ParameterNames.directory: 'new_full_app',
            ParameterNames.projectType: 'flutter',
            ParameterNames.template: 'app',
            ParameterNames.empty:
                false, // Explicitly create a non-empty project
          },
        );
        await testHarness.callToolWithRetry(request);

        expect(testProcessManager.commandsRan, [
          equalsCommand((
            command: [
              endsWith(flutterExecutableName),
              'create',
              '--template',
              'app',
              // Note: --empty is NOT present
              'new_full_app',
            ],
            workingDirectory: exampleFlutterAppRoot.path,
          )),
        ]);
      });

      test('fails with invalid platform for Flutter project', () async {
        testHarness.mcpClient.addRoot(exampleFlutterAppRoot);
        final request = CallToolRequest(
          name: createProjectTool.name,
          arguments: {
            ParameterNames.root: exampleFlutterAppRoot.uri,
            ParameterNames.directory: 'my_app_invalid_platform',
            ParameterNames.projectType: 'flutter',
            ParameterNames.platform: ['atari_jaguar', 'web'], // One invalid
          },
        );
        final result = await testHarness.callToolWithRetry(
          request,
          expectError: true,
        );

        expect(result.isError, isTrue);
        expect(
          (result.content.first as TextContent).text,
          allOf(
            contains('atari_jaguar is not a valid platform.'),
            contains(
              'Platforms `web`, `linux`, `macos`, `windows`, `android`, `ios` '
              'are the only allowed values',
            ),
          ),
        );
        expect(testProcessManager.commandsRan, isEmpty);
      });

      test('fails if projectType is missing', () async {
        testHarness.mcpClient.addRoot(dartCliAppRoot);
        final request = CallToolRequest(
          name: createProjectTool.name,
          arguments: {
            ParameterNames.root: dartCliAppRoot.uri,
            ParameterNames.directory: 'my_app_no_type',
          },
        );
        final result = await testHarness.callToolWithRetry(
          request,
          expectError: true,
        );

        expect(result.isError, isTrue);
        expect(
          (result.content.first as TextContent).text,
          contains('Required property "projectType" is missing'),
        );
        expect(testProcessManager.commandsRan, isEmpty);
      });

      test('fails with invalid projectType', () async {
        testHarness.mcpClient.addRoot(dartCliAppRoot);
        final request = CallToolRequest(
          name: createProjectTool.name,
          arguments: {
            ParameterNames.root: dartCliAppRoot.uri,
            ParameterNames.directory: 'my_app_invalid_type',
            ParameterNames.projectType: 'java', // Invalid type
          },
        );
        final result = await testHarness.callToolWithRetry(
          request,
          expectError: true,
        );

        expect(result.isError, isTrue);
        expect(
          (result.content.first as TextContent).text,
          contains('Only `dart` and `flutter` are allowed values.'),
        );
        expect(testProcessManager.commandsRan, isEmpty);
      });

      test('fails if directory (project name) is an absolute path', () async {
        testHarness.mcpClient.addRoot(dartCliAppRoot);
        final request = CallToolRequest(
          name: createProjectTool.name,
          arguments: {
            ParameterNames.root: dartCliAppRoot.uri,
            ParameterNames.directory: '/an/absolute/path/project',
            ParameterNames.projectType: 'dart',
          },
        );
        final result = await testHarness.callToolWithRetry(
          request,
          expectError: true,
        );

        expect(result.isError, isTrue);
        expect(
          (result.content.first as TextContent).text,
          contains('Directory must be a relative path'),
        );
        expect(testProcessManager.commandsRan, isEmpty);
      });

      test('requires a root to be passed', () async {
        testHarness.mcpClient.addRoot(dartCliAppRoot);
        final request = CallToolRequest(
          name: createProjectTool.name,
          arguments: {
            ParameterNames.directory: 'new_app',
            ParameterNames.projectType: 'dart',
            ParameterNames.template: 'cli',
          },
        );
        final result = await testHarness.callToolWithRetry(
          request,
          expectError: true,
        );

        expect(result.isError, true);
        expect(
          (result.content.first as TextContent).text,
          contains('missing `root` key'),
        );
        expect(testProcessManager.commandsRan, isEmpty);
      });
    });
  });
}
