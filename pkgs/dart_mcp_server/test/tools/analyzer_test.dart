// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp_server/src/mixins/analyzer.dart';
import 'package:dart_mcp_server/src/utils/constants.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../test_harness.dart';

void main() {
  late TestHarness testHarness;

  // TODO: Use setUpAll, currently this fails due to an apparent TestProcess
  // issue.
  setUp(() async {
    testHarness = await TestHarness.start();
  });

  group('analyzer tools', () {
    late Tool analyzeTool;

    setUp(() async {
      final tools = (await testHarness.mcpServerConnection.listTools()).tools;
      analyzeTool = tools.singleWhere(
        (t) => t.name == DartAnalyzerSupport.analyzeFilesTool.name,
      );
    });

    test('can analyze and re-analyze after changes', () async {
      final example = d.dir('example', [
        d.file('main.dart', 'void main() => 1 + "2";'),
      ]);
      await example.create();
      final exampleRoot = testHarness.rootForPath(example.io.path);
      testHarness.mcpClient.addRoot(exampleRoot);

      // Allow the notification to propagate, and the server to ask for the new
      // list of roots.
      await pumpEventQueue();

      final request = CallToolRequest(name: analyzeTool.name);
      var result = await testHarness.callToolWithRetry(request);
      expect(result.isError, isNot(true));
      expect(result.content, [
        isA<TextContent>().having(
          (t) => t.text,
          'text',
          contains(
            "The argument type 'String' can't be assigned to the parameter "
            "type 'num'.",
          ),
        ),
      ]);

      // Change the file to fix the error
      await d.dir('example', [
        d.file('main.dart', 'void main() => 1 + 2;'),
      ]).create();
      // Wait for the file watcher to pick up the change, the default delay for
      // a polling watcher is one second.
      await Future<void>.delayed(const Duration(seconds: 1));

      result = await testHarness.callToolWithRetry(request);
      expect(result.isError, isNot(true));
      expect(
        result.content.single,
        isA<TextContent>().having((t) => t.text, 'text', 'No errors'),
      );
    });

    test('can analyze a project with multiple errors (no paths)', () async {
      final example = d.dir('example', [
        d.file('main.dart', 'void main() => 1 + "2";'),
        d.file('other.dart', 'void other() => foo;'),
      ]);
      await example.create();
      final exampleRoot = testHarness.rootForPath(example.io.path);
      testHarness.mcpClient.addRoot(exampleRoot);

      await pumpEventQueue();

      final request = CallToolRequest(name: analyzeTool.name);
      final result = await testHarness.callToolWithRetry(request);
      expect(result.isError, isNot(true));
      expect(result.content, hasLength(2));
      expect(
        result.content,
        containsAll([
          isA<TextContent>().having(
            (t) => t.text,
            'text',
            contains("Undefined name 'foo'"),
          ),
          isA<TextContent>().having(
            (t) => t.text,
            'text',
            contains(
              "The argument type 'String' can't be assigned to the parameter "
              "type 'num'.",
            ),
          ),
        ]),
      );
    });

    test('can analyze a specific file', () async {
      final example = d.dir('example', [
        d.file('main.dart', 'void main() => 1 + "2";'),
        d.file('other.dart', 'void other() => foo;'),
      ]);
      await example.create();
      final exampleRoot = testHarness.rootForPath(example.io.path);
      testHarness.mcpClient.addRoot(exampleRoot);

      await pumpEventQueue();

      final request = CallToolRequest(
        name: analyzeTool.name,
        arguments: {
          ParameterNames.roots: [
            {
              ParameterNames.root: exampleRoot.uri,
              ParameterNames.paths: ['main.dart'],
            },
          ],
        },
      );
      final result = await testHarness.callToolWithRetry(request);
      expect(result.isError, isNot(true));
      expect(result.content, hasLength(1));
      expect(
        result.content.single,
        isA<TextContent>().having(
          (t) => t.text,
          'text',
          contains(
            "The argument type 'String' can't be assigned to the parameter "
            "type 'num'.",
          ),
        ),
      );
    });

    test('can analyze a specific directory', () async {
      final example = d.dir('example', [
        d.file('main.dart', 'void main() => 1 + "2";'),
        d.dir('sub', [d.file('other.dart', 'void other() => foo;')]),
      ]);
      await example.create();
      final exampleRoot = testHarness.rootForPath(example.io.path);
      testHarness.mcpClient.addRoot(exampleRoot);

      await pumpEventQueue();

      final request = CallToolRequest(
        name: analyzeTool.name,
        arguments: {
          ParameterNames.roots: [
            {
              ParameterNames.root: exampleRoot.uri,
              ParameterNames.paths: ['sub'],
            },
          ],
        },
      );
      final result = await testHarness.callToolWithRetry(request);
      expect(result.isError, isNot(true));
      expect(result.content, hasLength(1));
      expect(
        result.content.single,
        isA<TextContent>().having(
          (t) => t.text,
          'text',
          contains("Undefined name 'foo'"),
        ),
      );
    });

    test('handles a non-existent path', () async {
      final example = d.dir('example', [
        d.file('main.dart', 'void main() => 1 + "2";'),
      ]);
      await example.create();
      final exampleRoot = testHarness.rootForPath(example.io.path);
      testHarness.mcpClient.addRoot(exampleRoot);

      await pumpEventQueue();

      final request = CallToolRequest(
        name: analyzeTool.name,
        arguments: {
          ParameterNames.roots: [
            {
              ParameterNames.root: exampleRoot.uri,
              ParameterNames.paths: ['not_a_real_file.dart'],
            },
          ],
        },
      );
      final result = await testHarness.callToolWithRetry(request);
      expect(result.isError, isNot(true));
      expect(
        result.content.single,
        isA<TextContent>().having((t) => t.text, 'text', 'No errors'),
      );
    });

    test('handles an empty paths list for a root', () async {
      final example = d.dir('example', [
        d.file('main.dart', 'void main() => 1 + "2";'),
      ]);
      await example.create();
      final exampleRoot = testHarness.rootForPath(example.io.path);
      testHarness.mcpClient.addRoot(exampleRoot);

      await pumpEventQueue();

      final request = CallToolRequest(
        name: analyzeTool.name,
        arguments: {
          ParameterNames.roots: [
            {
              ParameterNames.root: exampleRoot.uri,
              ParameterNames.paths: <String>[], // Empty paths
            },
          ],
        },
      );
      final result = await testHarness.callToolWithRetry(request);
      expect(result.isError, isNot(true));
      expect(result.content, hasLength(1));
      expect(
        result.content.single,
        isA<TextContent>().having(
          (t) => t.text,
          'text',
          contains(
            "The argument type 'String' can't be assigned to the parameter "
            "type 'num'.",
          ),
        ),
      );
    });

    test('handles an empty roots list', () async {
      // We still need a root registered with the server so that the
      // prerequisites check passes.
      final example = d.dir('example', [
        d.file('main.dart', 'void main() => 1;'),
      ]);
      await example.create();
      final exampleRoot = testHarness.rootForPath(example.io.path);
      testHarness.mcpClient.addRoot(exampleRoot);
      await pumpEventQueue();

      final request = CallToolRequest(
        name: analyzeTool.name,
        arguments: {ParameterNames.roots: []},
      );
      final result = await testHarness.callToolWithRetry(
        request,
        expectError: true,
      );
      expect(result.isError, isTrue);
      expect(
        result.content.single,
        isA<TextContent>().having(
          (t) => t.text,
          'text',
          'No roots set. At least one root must be set in order to use this '
              'tool.',
        ),
      );
    });

    test('can analyze files in multiple roots', () async {
      final projectA = d.dir('project_a', [
        d.file('main.dart', 'void main() => 1 + "a";'),
      ]);
      await projectA.create();
      final projectARoot = testHarness.rootForPath(projectA.io.path);
      testHarness.mcpClient.addRoot(projectARoot);

      final projectB = d.dir('project_b', [
        d.file('other.dart', 'void other() => foo;'),
      ]);
      await projectB.create();
      final projectBRoot = testHarness.rootForPath(projectB.io.path);
      testHarness.mcpClient.addRoot(projectBRoot);

      await pumpEventQueue();

      final request = CallToolRequest(
        name: analyzeTool.name,
        arguments: {
          ParameterNames.roots: [
            {
              ParameterNames.root: projectARoot.uri,
              ParameterNames.paths: ['main.dart'],
            },
            {
              ParameterNames.root: projectBRoot.uri,
              ParameterNames.paths: ['other.dart'],
            },
          ],
        },
      );
      final result = await testHarness.callToolWithRetry(request);
      expect(result.isError, isNot(true));
      expect(result.content, hasLength(2));
      expect(
        result.content,
        containsAll([
          isA<TextContent>().having(
            (t) => t.text,
            'text',
            contains(
              "The argument type 'String' can't be assigned to the "
              "parameter type 'num'.",
            ),
          ),
          isA<TextContent>().having(
            (t) => t.text,
            'text',
            contains("Undefined name 'foo'"),
          ),
        ]),
      );
    });

    test('can look up symbols in a workspace', () async {
      final example = d.dir('lib', [
        d.file('awesome_class.dart', 'class MyAwesomeClass {}'),
      ]);
      await example.create();
      final exampleRoot = testHarness.rootForPath(example.io.path);
      testHarness.mcpClient.addRoot(exampleRoot);
      await pumpEventQueue();

      final result = await testHarness.callToolWithRetry(
        CallToolRequest(
          name: DartAnalyzerSupport.resolveWorkspaceSymbolTool.name,
          arguments: {ParameterNames.query: 'MyAwesomeClass'},
        ),
      );
      expect(result.isError, isNot(true));

      expect(
        result.content.single,
        isA<TextContent>().having(
          (t) => t.text,
          'text',
          contains('awesome_class.dart'),
        ),
      );
    });

    test('can get signature help', () async {
      final example = d.dir('example', [
        d.file('main.dart', '''
void main() {
  printIt(x: 1);
}

/// Just prints [x].
void printIt({required int x}) {
  print(x);
}
'''),
      ]);
      await example.create();
      final exampleRoot = testHarness.rootForPath(example.io.path);
      testHarness.mcpClient.addRoot(exampleRoot);

      await pumpEventQueue();

      final result = await testHarness.callToolWithRetry(
        CallToolRequest(
          name: DartAnalyzerSupport.signatureHelpTool.name,
          arguments: {
            ParameterNames.uri: p.join(exampleRoot.uri, 'main.dart'),
            ParameterNames.line: 1,
            ParameterNames.column: 12,
          },
        ),
      );
      expect(result.isError, isNot(true));

      expect(
        result.content.single,
        isA<TextContent>().having(
          (t) => t.text,
          'text',
          allOf(
            contains('Just prints [x].'), // From the doc comment
            contains('printIt({required int x})'), // The actual signature
          ),
        ),
      );
    });

    test('can get hover information', () async {
      final example = d.dir('example', [
        d.file('main.dart', '''
void main() {
  printIt(x: 1);
}

/// Just prints [x].
void printIt({required int x}) {
  print(x);
}
'''),
      ]);
      await example.create();
      final exampleRoot = testHarness.rootForPath(example.io.path);
      testHarness.mcpClient.addRoot(exampleRoot);
      await pumpEventQueue();

      final result = await testHarness.callToolWithRetry(
        CallToolRequest(
          name: DartAnalyzerSupport.hoverTool.name,
          arguments: {
            ParameterNames.uri: p.join(exampleRoot.uri, 'main.dart'),
            ParameterNames.line: 1,
            ParameterNames.column: 4,
          },
        ),
      );
      expect(result.isError, isNot(true));

      expect(
        result.content.single,
        isA<TextContent>().having(
          (t) => t.text,
          'text',
          allOf(
            contains('Just prints [x].'), // Doc comment
            contains('void printIt({required int x})'), // Function signature
            contains('void Function({required int x})'), // The type of it
          ),
        ),
      );
    });

    test('cannot analyze without roots set', () async {
      final result = await testHarness.callTool(
        CallToolRequest(name: DartAnalyzerSupport.analyzeFilesTool.name),
        expectError: true,
      );
      expect(
        result.content.single,
        isA<TextContent>().having(
          (t) => t.text,
          'text',
          contains('No roots set'),
        ),
      );
    });

    test('cannot look up symbols without roots set', () async {
      final result = await testHarness.callTool(
        CallToolRequest(
          name: DartAnalyzerSupport.resolveWorkspaceSymbolTool.name,
          arguments: {ParameterNames.query: 'DartAnalyzerSupport'},
        ),
        expectError: true,
      );
      expect(
        result.content.single,
        isA<TextContent>().having(
          (t) => t.text,
          'text',
          contains('No roots set'),
        ),
      );
    });

    test('cannot get hover information without roots set', () async {
      final result = await testHarness.callTool(
        CallToolRequest(
          name: DartAnalyzerSupport.hoverTool.name,
          arguments: {
            ParameterNames.uri: 'file:///any/file.dart',
            ParameterNames.line: 0,
            ParameterNames.column: 0,
          },
        ),
        expectError: true,
      );
      expect(
        result.content.single,
        isA<TextContent>().having(
          (t) => t.text,
          'text',
          contains('No roots set'),
        ),
      );
    });
  });
}
