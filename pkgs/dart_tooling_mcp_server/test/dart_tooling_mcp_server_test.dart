// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:dart_tooling_mcp_server/src/mixins/analyzer.dart';
import 'package:dart_tooling_mcp_server/src/mixins/dart_cli.dart';
import 'package:dart_tooling_mcp_server/src/mixins/dtd.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import 'test_harness.dart';

void main() {
  late TestHarness testHarness;

  // TODO: Use setUpAll, currently this fails due to an apparent TestProcess
  // issue.
  setUp(() async {
    testHarness = await TestHarness.start();
  });

  group('flutter tools', () {
    test('can take a screenshot', () async {
      await testHarness.connectToDtd();

      await testHarness.startDebugSession(
        counterAppPath,
        'lib/main.dart',
        isFlutter: true,
      );

      final tools = (await testHarness.mcpServerConnection.listTools()).tools;
      final screenshotTool = tools.singleWhere(
        (t) => t.name == DartToolingDaemonSupport.screenshotTool.name,
      );
      final screenshotResult = await testHarness.callToolWithRetry(
        CallToolRequest(name: screenshotTool.name),
      );
      expect(screenshotResult.content.single, {
        'data': anything,
        'mimeType': 'image/png',
        'type': ImageContent.expectedType,
      });
    });

    test('can perform a hot reload', () async {
      await testHarness.connectToDtd();

      await testHarness.startDebugSession(
        counterAppPath,
        'lib/main.dart',
        isFlutter: true,
      );

      final tools = (await testHarness.mcpServerConnection.listTools()).tools;
      final hotReloadTool = tools.singleWhere(
        (t) => t.name == DartToolingDaemonSupport.hotReloadTool.name,
      );
      final hotReloadResult = await testHarness.callToolWithRetry(
        CallToolRequest(name: hotReloadTool.name),
      );

      expect(hotReloadResult.isError, isNot(true));
      expect(hotReloadResult.content, [
        TextContent(text: 'Hot reload succeeded.'),
      ]);
    });
  });

  group('analysis', () {
    late Tool analyzeTool;

    setUp(() async {
      final tools = (await testHarness.mcpServerConnection.listTools()).tools;
      analyzeTool = tools.singleWhere(
        (t) => t.name == DartAnalyzerSupport.analyzeFilesTool.name,
      );
    });

    test('can analyze a project', () async {
      final counterAppRoot = rootForPath(counterAppPath);
      testHarness.mcpClient.addRoot(counterAppRoot);
      // Allow the notification to propagate, and the server to ask for the new
      // list of roots.
      await pumpEventQueue();

      final request = CallToolRequest(
        name: analyzeTool.name,
        arguments: {
          'roots': [
            {
              'root': counterAppRoot.uri,
              'paths': ['lib/main.dart'],
            },
          ],
        },
      );
      final result = await testHarness.callToolWithRetry(request);
      expect(result.isError, isNot(true));
      expect(result.content, isEmpty);
    });

    test('can handle project changes', () async {
      final example = d.dir('example', [
        d.file('main.dart', 'void main() => 1 + "2";'),
      ]);
      await example.create();
      final exampleRoot = rootForPath(example.io.path);
      testHarness.mcpClient.addRoot(exampleRoot);

      // Allow the notification to propagate, and the server to ask for the new
      // list of roots.
      await pumpEventQueue();

      final request = CallToolRequest(
        name: analyzeTool.name,
        arguments: {
          'roots': [
            {
              'root': exampleRoot.uri,
              'paths': ['main.dart'],
            },
          ],
        },
      );
      var result = await testHarness.callToolWithRetry(request);
      expect(result.isError, isNot(true));
      expect(result.content, [
        TextContent(
          text:
              "Error: The argument type 'String' can't be assigned to the "
              "parameter type 'num'. ",
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
      expect(result.content, isEmpty);
    });
  });

  group('dart cli', () {
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

      final dartFixContent =
          File(p.join(copyDartCliAppsBin, 'dart_fix.dart')).readAsStringSync();
      expect(dartFixContent, contains('var myObject = MyClass();'));

      final dartFormatContent =
          File(
            p.join(copyDartCliAppsBin, 'dart_format.dart'),
          ).readAsStringSync();
      expect(dartFormatContent, contains('void main() {print("hello");}'));

      addTearDown(() async {
        // Delete the copy.
        await Directory(copyDartCliAppsBin).delete(recursive: true);
      });
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
        contains('void main() {\n  print("hello");\n}\n'),
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
        contains('void main() {\n  print("hello");\n}\n'),
      );
      final secondFormattedFile = File(
        p.join(copyDartCliAppsBin, 'dart_format_1.dart'),
      );
      expect(
        secondFormattedFile.readAsStringSync(),
        contains('void main() {\n  print("hello");\n}\n'),
      );

      // Check that the other files in the directory were unmodified.
      final firstUnformattedFile = File(
        p.join(copyDartCliAppsBin, 'dart_format_2.dart'),
      );
      expect(
        firstUnformattedFile.readAsStringSync(),
        contains('void main() {print("hello");}'),
      );
      final secondUnormattedFile = File(
        p.join(copyDartCliAppsBin, 'dart_format_3.dart'),
      );
      expect(
        secondUnormattedFile.readAsStringSync(),
        contains('void main() {print("hello");}'),
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
