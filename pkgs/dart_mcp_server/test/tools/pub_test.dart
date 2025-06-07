// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io' hide File;
import 'dart:io' as io show File;

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp_server/src/mixins/pub.dart';
import 'package:dart_mcp_server/src/utils/constants.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_harness.dart';

void main() {
  late TestHarness testHarness;
  late TestProcessManager testProcessManager;
  late Root testRoot;
  late Tool dartPubTool;
  late FileSystem fileSystem;

  final fakeAppPath = io.File.fromUri(Uri.parse('/fake_app/')).path;

  for (final appKind in const ['dart', 'flutter']) {
    final executableName =
        '$appKind${Platform.isWindows
            ? appKind == 'dart'
                ? '.exe'
                : '.bat'
            : ''}';
    group('$appKind app', () {
      // TODO: Use setUpAll, currently this fails due to an apparent TestProcess
      // issue.
      setUp(() async {
        fileSystem = MemoryFileSystem(
          style:
              Platform.isWindows
                  ? FileSystemStyle.windows
                  : FileSystemStyle.posix,
        );
        fileSystem.file(p.join(fakeAppPath, 'pubspec.yaml'))
          ..createSync(recursive: true)
          ..writeAsStringSync(
            appKind == 'flutter' ? flutterPubspec : dartPubspec,
          );
        testHarness = await TestHarness.start(
          inProcess: true,
          fileSystem: fileSystem,
        );
        testProcessManager =
            testHarness.serverConnectionPair.server!.processManager
                as TestProcessManager;
        testRoot = testHarness.rootForPath(fakeAppPath);

        testHarness.mcpClient.addRoot(testRoot);
        await pumpEventQueue();

        final tools = (await testHarness.mcpServerConnection.listTools()).tools;
        dartPubTool = tools.singleWhere(
          (t) => t.name == PubSupport.pubTool.name,
        );
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

          // Verify the command was sent to the process manager without error.
          expect(result.isError, isNot(true));
          expect(testProcessManager.commandsRan, [
            equalsCommand((
              command: [endsWith(executableName), 'pub', 'add', 'foo'],
              workingDirectory: testRoot.path,
            )),
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

          // Verify the command was sent to the process manager without error.
          expect(result.isError, isNot(true));
          expect(testProcessManager.commandsRan, [
            equalsCommand((
              command: [endsWith(executableName), 'pub', 'remove', 'foo'],
              workingDirectory: testRoot.path,
            )),
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

          // Verify the command was sent to the process manager without error.
          expect(result.isError, isNot(true));
          expect(testProcessManager.commandsRan, [
            equalsCommand((
              command: [endsWith(executableName), 'pub', 'get'],
              workingDirectory: testRoot.path,
            )),
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

          // Verify the command was sent to the process manager without error.
          expect(result.isError, isNot(true));
          expect(testProcessManager.commandsRan, [
            equalsCommand((
              command: [endsWith(executableName), 'pub', 'upgrade'],
              workingDirectory: testRoot.path,
            )),
          ]);
        });

        test('in a subdir of an a root', () async {
          fileSystem.file(p.join(fakeAppPath, 'subdir', 'pubspec.yaml'))
            ..createSync(recursive: true)
            ..writeAsStringSync(
              appKind == 'flutter' ? flutterPubspec : dartPubspec,
            );
          final request = CallToolRequest(
            name: dartPubTool.name,
            arguments: {
              ParameterNames.command: 'get',
              ParameterNames.roots: [
                {ParameterNames.root: p.join(testRoot.uri, 'subdir')},
              ],
            },
          );
          final result = await testHarness.callToolWithRetry(request);

          // Verify the command was sent to the process manager without error.
          expect(result.isError, isNot(true));
          expect(testProcessManager.commandsRan, [
            equalsCommand((
              command: [endsWith(executableName), 'pub', 'get'],
              workingDirectory: p.join(fakeAppPath, 'subdir'),
            )),
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
    });
  }
}

final dartPubspec = '''
name: dart_app
environment:
  sdk: ^3.7.0
''';

final flutterPubspec = '''
name: flutter_app
environment:
  sdk: ^3.7.0
dependencies:
  flutter:
    sdk: flutter
''';
