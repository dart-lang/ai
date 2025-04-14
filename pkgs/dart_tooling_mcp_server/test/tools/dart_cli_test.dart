// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:dart_tooling_mcp_server/src/mixins/dart_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_harness.dart';

void main() {
  late TestHarness testHarness;

  // TODO: Use setUpAll, currently this fails due to an apparent TestProcess
  // issue.
  setUp(() async {
    testHarness = await TestHarness.start();
  });
  group('dart cli tools', () {
    late Tool dartFixTool;
    late Tool dartFormatTool;
    late String copyDartCliAppsBin;
    const copyDirectoryName = 'bin_copy';

    Future<void> copyDartCliAppAndVerifyContents() async {
      // Copy the original `dart_cli_app` directory so that changes from these
      // test runs do not affect the original test_fixture code. Copy inside of
      // the `dart_cli_app` folder so that the `analysis_options.yaml` file
      // applies to the copied directory.
      // TODO(https://github.com/dart-lang/ai/issues/51): it would be better to
      // copy this to a temp directory.
      copyDartCliAppsBin = p.join(dartCliAppsPath, copyDirectoryName);
      await _copyDirectory(
        Directory(p.join(dartCliAppsPath, 'bin')),
        Directory(copyDartCliAppsBin),
      );

      addTearDown(() async {
        // Delete the copy.
        await Directory(copyDartCliAppsBin).delete(recursive: true);
      });

      final dartFixContent =
          File(p.join(copyDartCliAppsBin, 'dart_fix.dart')).readAsStringSync();
      expect(dartFixContent, contains('var myObject = MyClass();'));

      // Read the initial (formatted) contents, and then remove the newlines and
      // write that as the new contents.
      final dartFormatFile = File(
        p.join(copyDartCliAppsBin, 'dart_format.dart'),
      );
      final dartFormatContent = dartFormatFile.readAsStringSync();
      final newContent = dartFormatContent.replaceFirst(
        "\n  print('hello');\n",
        "print('hello');",
      );
      expect(dartFormatContent, isNot(newContent));
      await dartFormatFile.writeAsString(newContent);
    }

    setUp(() async {
      await copyDartCliAppAndVerifyContents();

      final tools = (await testHarness.mcpServerConnection.listTools()).tools;
      dartFixTool = tools.singleWhere(
        (t) => t.name == DartCliSupport.dartFixTool.name,
      );
      dartFormatTool = tools.singleWhere(
        (t) => t.name == DartCliSupport.dartFormatTool.name,
      );
    });

    test('can run dart fix', () async {
      final root = rootForPath(copyDartCliAppsBin);
      testHarness.mcpClient.addRoot(root);
      await pumpEventQueue();

      final request = CallToolRequest(
        name: dartFixTool.name,
        arguments: {
          'roots': [
            {'root': root.uri},
          ],
        },
      );
      final result = await testHarness.callToolWithRetry(request);

      expect(result.isError, isNot(true));
      expect(
        (result.content.single as TextContent).text,
        contains('Computing fixes in $copyDirectoryName...'),
      );
      expect(
        (result.content.single as TextContent).text,
        contains('Applying fixes...'),
      );
      expect(
        (result.content.single as TextContent).text,
        isNot(contains('Nothing to fix!')),
      );

      // Check that the file was modified
      final fixedContent =
          File(p.join(copyDartCliAppsBin, 'dart_fix.dart')).readAsStringSync();
      expect(fixedContent, contains('final myObject = MyClass();'));

      // Run dart fix again and verify there are no changes.
      final secondResult = await testHarness.callToolWithRetry(request);
      expect(secondResult.isError, isNot(true));
      expect(
        (secondResult.content.single as TextContent).text,
        contains('Nothing to fix!'),
      );
    });

    test('can run dart format', () async {
      final root = rootForPath(copyDartCliAppsBin);
      testHarness.mcpClient.addRoot(root);
      await pumpEventQueue();

      final request = CallToolRequest(
        name: dartFormatTool.name,
        arguments: {
          'roots': [
            {'root': root.uri},
          ],
        },
      );
      final result = await testHarness.callToolWithRetry(request);
      expect(result.isError, isNot(true));
      expect(
        (result.content.single as TextContent).text,
        contains(
          'Formatted ${Directory(copyDartCliAppsBin).listSync().length} files '
          '(1 changed)',
        ),
      );

      // Check that the file was modified
      final formattedFile = File(
        p.join(copyDartCliAppsBin, 'dart_format.dart'),
      );
      expect(
        formattedFile.readAsStringSync(),
        contains("void main() {\n  print('hello');\n}\n"),
      );

      // Run dart format again and verify there are no changes.
      final secondResult = await testHarness.callToolWithRetry(request);
      expect(secondResult.isError, isNot(true));
      expect(
        (secondResult.content.single as TextContent).text,
        contains(
          'Formatted ${Directory(copyDartCliAppsBin).listSync().length} files '
          '(0 changed)',
        ),
      );
    });

    test('can run dart format with paths', () async {
      // Create copies of the file with formatting issues.
      final file = File(p.join(copyDartCliAppsBin, 'dart_format.dart'));
      expect(
        file.readAsStringSync(),
        contains("void main() {print('hello');}"),
      );
      for (var i = 1; i <= 3; i++) {
        await file.copy(p.join(copyDartCliAppsBin, 'dart_format_$i.dart'));
      }

      final root = rootForPath(copyDartCliAppsBin);
      testHarness.mcpClient.addRoot(root);
      await pumpEventQueue();

      final request = CallToolRequest(
        name: dartFormatTool.name,
        arguments: {
          'roots': [
            {
              'root': root.uri,
              'paths': ['dart_format.dart', 'dart_format_1.dart'],
            },
          ],
        },
      );
      final result = await testHarness.callToolWithRetry(request);
      expect(result.isError, isNot(true));
      expect(
        (result.content.single as TextContent).text,
        contains('Formatted 2 files (2 changed)'),
      );

      // Check that the files were modified
      final firstFormattedFile = File(
        p.join(copyDartCliAppsBin, 'dart_format.dart'),
      );
      expect(
        firstFormattedFile.readAsStringSync(),
        contains("void main() {\n  print('hello');\n}\n"),
      );
      final secondFormattedFile = File(
        p.join(copyDartCliAppsBin, 'dart_format_1.dart'),
      );
      expect(
        secondFormattedFile.readAsStringSync(),
        contains("void main() {\n  print('hello');\n}\n"),
      );

      // Check that the other files in the directory were unmodified.
      final firstUnformattedFile = File(
        p.join(copyDartCliAppsBin, 'dart_format_2.dart'),
      );
      expect(
        firstUnformattedFile.readAsStringSync(),
        contains("void main() {print('hello');}"),
      );
      final secondUnformattedFile = File(
        p.join(copyDartCliAppsBin, 'dart_format_3.dart'),
      );
      expect(
        secondUnformattedFile.readAsStringSync(),
        contains("void main() {print('hello');}"),
      );
    });
  });
}

/// Helper function to recursively copy a directory.
Future<void> _copyDirectory(Directory source, Directory destination) async {
  await destination.create(recursive: true);
  // Add a small delay to allow filesystem changes to propagate.
  await Future<void>.delayed(const Duration(milliseconds: 10));

  assert(await source.exists());
  assert(await destination.exists());

  await for (var entity in source.list(recursive: false)) {
    final newPath = p.join(destination.path, p.basename(entity.path));
    if (entity is File) {
      await entity.copy(newPath);
    } else if (entity is Directory) {
      await _copyDirectory(entity, Directory(newPath));
    }
  }
}
