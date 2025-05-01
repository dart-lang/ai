// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_mcp/server.dart';
import 'package:dart_tooling_mcp_server/src/utils/cli_utils.dart';
import 'package:dart_tooling_mcp_server/src/utils/constants.dart';
import 'package:process/process.dart';
import 'package:test/fake.dart';
import 'package:test/test.dart';

void main() {
  final processManager = FakeProcessManager();

  test('cannot run commands with roots outside of known roots', () async {
    final result = await runCommandInRoots(
      CallToolRequest(
        name: 'foo',
        arguments: {
          ParameterNames.roots: [
            {ParameterNames.root: 'file:///bar/'},
          ],
        },
      ),
      command: ['fake'],
      commandDescription: '',
      processManager: processManager,
      knownRoots: [Root(uri: 'file:///foo/')],
    );
    expect(result.isError, isTrue);
    expect(
      result.content.single,
      isA<TextContent>().having(
        (t) => t.text,
        'text',
        contains('Invalid root file:///bar/'),
      ),
    );
  });

  test('cannot run commands with paths outside of known roots', () async {
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
      command: ['fake'],
      commandDescription: '',
      processManager: processManager,
      knownRoots: [Root(uri: 'file:///foo/')],
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
}

class FakeProcessManager extends Fake implements ProcessManager {}
