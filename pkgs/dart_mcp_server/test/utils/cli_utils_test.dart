// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp_server/src/utils/cli_utils.dart';
import 'package:dart_mcp_server/src/utils/constants.dart';
import 'package:dart_mcp_server/src/utils/sdk.dart';
import 'package:file/memory.dart';
import 'package:process/process.dart';
import 'package:test/fake.dart';
import 'package:test/test.dart';

import '../test_harness.dart';

void main() {
  late MemoryFileSystem fileSystem;

  setUp(() {
    fileSystem = MemoryFileSystem();
  });

  group('can run commands', () {
    late TestProcessManager processManager;
    setUp(() async {
      processManager = TestProcessManager();
    });

    test('can run commands with exact matches for roots', () async {
      final result = await runCommandInRoots(
        CallToolRequest(
          name: 'foo',
          arguments: {
            ParameterNames.roots: [
              {ParameterNames.root: 'file:///bar/'},
            ],
          },
        ),
        commandForRoot: (_, _, _) => 'testCommand',
        arguments: ['a', 'b'],
        commandDescription: '',
        processManager: processManager,
        knownRoots: [Root(uri: 'file:///bar/')],
        fileSystem: fileSystem,
        sdk: Sdk(),
      );
      expect(result.isError, isNot(true));
      expect(processManager.commandsRan, [
        equalsCommand((
          command: ['testCommand', 'a', 'b'],
          workingDirectory: '/bar/',
        )),
      ]);
    });

    test(
      'can run commands with roots that are subdirectories of known roots',
      () async {
        expect(fileSystem.directory('/bar/baz').existsSync(), false);
        final result = await runCommandInRoots(
          CallToolRequest(
            name: 'foo',
            arguments: {
              ParameterNames.roots: [
                {ParameterNames.root: 'file:///bar/baz/'},
              ],
            },
          ),
          commandForRoot: (_, _, _) => 'testCommand',
          commandDescription: '',
          processManager: processManager,
          knownRoots: [Root(uri: 'file:///bar/')],
          fileSystem: fileSystem,
          sdk: Sdk(),
        );
        expect(result.isError, isNot(true));
        expect(processManager.commandsRan, [
          equalsCommand((
            command: ['testCommand'],
            workingDirectory: '/bar/baz/',
          )),
        ]);
        expect(fileSystem.directory('/bar/baz').existsSync(), true);
      },
    );

    test('can run commands with missing trailing slashes for roots', () async {
      final result = await runCommandInRoots(
        CallToolRequest(
          name: 'foo',
          arguments: {
            ParameterNames.roots: [
              {ParameterNames.root: 'file:///bar'},
            ],
          },
        ),
        commandForRoot: (_, _, _) => 'testCommand',
        arguments: ['a', 'b'],
        commandDescription: '',
        processManager: processManager,
        knownRoots: [Root(uri: 'file:///bar/')],
        fileSystem: fileSystem,
        sdk: Sdk(),
      );
      expect(result.isError, isNot(true));
      expect(processManager.commandsRan, [
        equalsCommand((
          command: ['testCommand', 'a', 'b'],
          workingDirectory: '/bar',
        )),
      ]);
    });

    test('can run commands with extra trailing slashes for roots', () async {
      final result = await runCommandInRoots(
        CallToolRequest(
          name: 'foo',
          arguments: {
            ParameterNames.roots: [
              {ParameterNames.root: 'file:///bar/'},
            ],
          },
        ),
        commandForRoot: (_, _, _) => 'testCommand',
        arguments: ['a', 'b'],
        commandDescription: '',
        processManager: processManager,
        knownRoots: [Root(uri: 'file:///bar')],
        fileSystem: fileSystem,
        sdk: Sdk(),
      );
      expect(result.isError, isNot(true));
      expect(processManager.commandsRan, [
        equalsCommand((
          command: ['testCommand', 'a', 'b'],
          workingDirectory: '/bar/',
        )),
      ]);
    });

    test('with paths inside of known roots', () async {
      final paths = ['file:///foo/', 'file:///foo', './', '.'];
      final result = await runCommandInRoots(
        CallToolRequest(
          name: 'foo',
          arguments: {
            ParameterNames.roots: [
              {ParameterNames.root: 'file:///foo', ParameterNames.paths: paths},
              {
                ParameterNames.root: 'file:///foo/',
                ParameterNames.paths: paths,
              },
            ],
          },
        ),
        commandForRoot: (_, _, _) => 'fake',
        commandDescription: '',
        processManager: processManager,
        knownRoots: [Root(uri: 'file:///foo/')],
        fileSystem: fileSystem,
        sdk: Sdk(),
      );
      expect(
        result.isError,
        isNot(true),
        reason: result.content.map((c) => (c as TextContent).text).join('\n'),
      );
      expect(
        processManager.commandsRan,
        unorderedEquals([
          equalsCommand((
            command: ['fake', ...paths],
            workingDirectory: '/foo/',
          )),
          equalsCommand((
            command: ['fake', ...paths],
            workingDirectory: '/foo',
          )),
        ]),
      );
    });
  });

  group('cannot run commands', () {
    final processManager = FakeProcessManager();

    test('with roots outside of known roots', () async {
      for (var invalidRoot in ['file:///bar/', 'file:///foo/../bar/']) {
        final result = await runCommandInRoots(
          CallToolRequest(
            name: 'foo',
            arguments: {
              ParameterNames.roots: [
                {ParameterNames.root: invalidRoot},
              ],
            },
          ),
          commandForRoot: (_, _, _) => 'fake',
          commandDescription: '',
          processManager: processManager,
          knownRoots: [Root(uri: 'file:///foo/')],
          fileSystem: fileSystem,
          sdk: Sdk(),
        );
        expect(result.isError, isTrue);
        expect(
          result.content.single,
          isA<TextContent>().having(
            (t) => t.text,
            'text',
            allOf(contains('Invalid root $invalidRoot')),
          ),
        );
      }
    });

    test('with paths outside of known roots', () async {
      final result = await runCommandInRoots(
        CallToolRequest(
          name: 'foo',
          arguments: {
            ParameterNames.roots: [
              {
                ParameterNames.root: 'file:///foo/',
                ParameterNames.paths: [
                  'file:///bar/',
                  '../baz/',
                  'zip/../../zap/',
                  'ok.dart',
                ],
              },
            ],
          },
        ),
        commandForRoot: (_, _, _) => 'fake',
        commandDescription: '',
        processManager: processManager,
        knownRoots: [Root(uri: 'file:///foo/')],
        fileSystem: fileSystem,
        sdk: Sdk(),
      );
      expect(result.isError, isTrue);
      expect(
        result.content.single,
        isA<TextContent>().having(
          (t) => t.text,
          'text',
          allOf(
            contains('Paths are not allowed to escape their project root'),
            contains('bar/'),
            contains('baz/'),
            contains('zap/'),
            isNot(contains('ok.dart')),
          ),
        ),
      );
    });
  });
}

class FakeProcessManager extends Fake implements ProcessManager {}
