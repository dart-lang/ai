// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/server.dart';
import 'package:dart_mcp_server/src/mixins/file_system.dart';
import 'package:dart_mcp_server/src/utils/names.dart';
import 'package:file/memory.dart';
import 'package:test/test.dart';

import '../test_harness.dart';

void main() {
  late TestHarness testHarness;
  late MemoryFileSystem memFs;
  late Root root;

  setUp(() async {
    memFs = MemoryFileSystem();
    // Create the root directory.
    await memFs.directory('/workspace').create(recursive: true);

    testHarness = await TestHarness.start(
      inProcess: true,
      fileSystem: memFs,
    );
    root = Root(uri: memFs.directory('/workspace').uri.toString());
    testHarness.mcpClient.addRoot(root);
  });

  Future<CallToolResult> readFile(String path) =>
      testHarness.callTool(
        CallToolRequest(
          name: FileAccessSupport.readFileTool.name,
          arguments: {ParameterNames.path: path},
        ),
      );

  Future<CallToolResult> writeFile(String path, String contents) =>
      testHarness.callTool(
        CallToolRequest(
          name: FileAccessSupport.writeFileTool.name,
          arguments: {
            ParameterNames.path: path,
            ParameterNames.contents: contents,
          },
        ),
      );

  Future<CallToolResult> deleteFile(String path) =>
      testHarness.callTool(
        CallToolRequest(
          name: FileAccessSupport.deleteFileTool.name,
          arguments: {ParameterNames.path: path},
        ),
      );

  Future<CallToolResult> listFiles(String path) =>
      testHarness.callTool(
        CallToolRequest(
          name: FileAccessSupport.listFilesTool.name,
          arguments: {ParameterNames.path: path},
        ),
      );

  group('FileAccessSupport', () {
    group('read_file', () {
      test('reads an existing file', () async {
        await memFs
            .file('/workspace/hello.txt')
            .writeAsString('hello world');

        final result = await readFile('file:///workspace/hello.txt');
        expect(result.isError, isNot(isTrue));
        final text = (result.content.first as TextContent).text;
        expect(text, 'hello world');
      });

      test('returns error for non-existent file', () async {
        final errorResult = await testHarness.callTool(
          CallToolRequest(
            name: FileAccessSupport.readFileTool.name,
            arguments: {
              ParameterNames.path: 'file:///workspace/missing.txt',
            },
          ),
          expectError: true,
        );
        expect(errorResult.isError, isTrue);
      });

      test('returns error for path outside roots', () async {
        final errorResult = await testHarness.callTool(
          CallToolRequest(
            name: FileAccessSupport.readFileTool.name,
            arguments: {
              ParameterNames.path: 'file:///etc/passwd',
            },
          ),
          expectError: true,
        );
        expect(errorResult.isError, isTrue);
      });
    });

    group('write_file', () {
      test('writes a new file', () async {
        final result = await writeFile(
          'file:///workspace/new.txt',
          'new content',
        );
        expect(result.isError, isNot(isTrue));

        final file = memFs.file('/workspace/new.txt');
        expect(await file.exists(), isTrue);
        expect(await file.readAsString(), 'new content');
      });

      test('overwrites an existing file', () async {
        await memFs.file('/workspace/existing.txt').writeAsString('old');

        await writeFile('file:///workspace/existing.txt', 'new');

        expect(
          await memFs.file('/workspace/existing.txt').readAsString(),
          'new',
        );
      });

      test('creates missing parent directories', () async {
        final result = await writeFile(
          'file:///workspace/a/b/c.txt',
          'deep',
        );
        expect(result.isError, isNot(isTrue));
        expect(
          await memFs.file('/workspace/a/b/c.txt').readAsString(),
          'deep',
        );
      });

      test('returns error for path outside roots', () async {
        final errorResult = await testHarness.callTool(
          CallToolRequest(
            name: FileAccessSupport.writeFileTool.name,
            arguments: {
              ParameterNames.path: 'file:///tmp/escape.txt',
              ParameterNames.contents: 'escaped',
            },
          ),
          expectError: true,
        );
        expect(errorResult.isError, isTrue);
        expect(
          await memFs.file('/tmp/escape.txt').exists(),
          isFalse,
        );
      });
    });

    group('delete_file', () {
      test('deletes an existing file', () async {
        await memFs.file('/workspace/to_delete.txt').writeAsString('bye');

        final result = await deleteFile('file:///workspace/to_delete.txt');
        expect(result.isError, isNot(isTrue));
        expect(await memFs.file('/workspace/to_delete.txt').exists(), isFalse);
      });

      test('returns error for non-existent file', () async {
        final errorResult = await testHarness.callTool(
          CallToolRequest(
            name: FileAccessSupport.deleteFileTool.name,
            arguments: {
              ParameterNames.path: 'file:///workspace/ghost.txt',
            },
          ),
          expectError: true,
        );
        expect(errorResult.isError, isTrue);
      });

      test('returns error for path outside roots', () async {
        await memFs.file('/tmp/secret.txt').create(recursive: true);

        final errorResult = await testHarness.callTool(
          CallToolRequest(
            name: FileAccessSupport.deleteFileTool.name,
            arguments: {
              ParameterNames.path: 'file:///tmp/secret.txt',
            },
          ),
          expectError: true,
        );
        expect(errorResult.isError, isTrue);
        expect(await memFs.file('/tmp/secret.txt').exists(), isTrue);
      });
    });

    group('list_files', () {
      test('lists directory contents', () async {
        await memFs.file('/workspace/a.txt').writeAsString('a');
        await memFs.file('/workspace/b.txt').writeAsString('b');
        await memFs.directory('/workspace/subdir').create();

        final result = await listFiles('file:///workspace/');
        expect(result.isError, isNot(isTrue));

        final text = (result.content.first as TextContent).text;
        final entries =
            (jsonDecode(text) as List).cast<Map<String, Object?>>();
        final uris = entries.map((e) => e['uri'] as String).toList();
        final kinds = {
          for (final e in entries) e['uri'] as String: e['kind'] as String,
        };

        expect(uris, containsAll([
          contains('a.txt'),
          contains('b.txt'),
          contains('subdir'),
        ]));
        expect(kinds.values, containsAll(['file', 'file', 'directory']));
      });

      test('returns error for non-existent directory', () async {
        final errorResult = await testHarness.callTool(
          CallToolRequest(
            name: FileAccessSupport.listFilesTool.name,
            arguments: {
              ParameterNames.path: 'file:///workspace/no_such_dir/',
            },
          ),
          expectError: true,
        );
        expect(errorResult.isError, isTrue);
      });

      test('returns error for path outside roots', () async {
        final errorResult = await testHarness.callTool(
          CallToolRequest(
            name: FileAccessSupport.listFilesTool.name,
            arguments: {
              ParameterNames.path: 'file:///etc/',
            },
          ),
          expectError: true,
        );
        expect(errorResult.isError, isTrue);
      });
    });

    group('relative paths', () {
      test('resolves relative path against single root', () async {
        await memFs.file('/workspace/rel.txt').writeAsString('relative!');

        final result = await readFile('rel.txt');
        expect(result.isError, isNot(isTrue));
        expect((result.content.first as TextContent).text, 'relative!');
      });

      test('rejects relative path when multiple roots are configured',
          () async {
        // Add a second root.
        final root2 = Root(
          uri: memFs.directory('/workspace2').uri.toString(),
        );
        await memFs.directory('/workspace2').create();
        testHarness.mcpClient.addRoot(root2);

        // Give the server a moment to receive the updated roots.
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final errorResult = await testHarness.callTool(
          CallToolRequest(
            name: FileAccessSupport.readFileTool.name,
            arguments: {ParameterNames.path: 'ambiguous.txt'},
          ),
          expectError: true,
        );
        expect(errorResult.isError, isTrue);
      });
    });

    group('tool definitions', () {
      test('all tools are registered', () async {
        final tools = (await testHarness.mcpServerConnection.listTools()).tools;
        final toolNames = tools.map((t) => t.name).toList();
        for (final tool in FileAccessSupport.allTools) {
          expect(toolNames, contains(tool.name));
        }
      });
    });
  });
}
