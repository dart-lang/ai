// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/server.dart';
import 'package:dart_mcp_server/src/mixins/grep_packages.dart';
import 'package:dart_mcp_server/src/mixins/package_uri_reader.dart';
import 'package:dart_mcp_server/src/utils/names.dart';
import 'package:process/process.dart';
import 'package:test/test.dart';

import '../test_harness.dart';

void main() {
  late TestHarness testHarness;
  late Root counterAppRoot;

  Future<CallToolResult> grep({
    required List<String> packageNames,
    required List<String> arguments,
    String? searchDir,
  }) {
    final args = <String, Object?>{
      ParameterNames.root: counterAppRoot.uri,
      ParameterNames.packageNames: packageNames,
      ParameterNames.arguments: arguments,
    };
    if (searchDir != null) {
      args[ParameterNames.searchDir] = searchDir;
    }
    return testHarness.callTool(
      CallToolRequest(
        name: GrepSupport.ripGrepPackagesTool.name,
        arguments: args,
      ),
    );
  }

  setUpAll(() async {
    testHarness = await TestHarness.start(
      inProcess: true,
      processManager: const LocalProcessManager(),
    );
    // Allow it to install ripgrep if necessary.
    testHarness.mcpClient.registerElicitationHandler(
      (_) => ElicitResult(action: ElicitationAction.accept),
    );
    counterAppRoot = testHarness.rootForPath(counterAppPath);
    testHarness.mcpClient.addRoot(counterAppRoot);
  });

  group('RipGrepSupport', () {
    test('finds matches in project files', () async {
      final result = await grep(
        packageNames: ['counter_app'],
        arguments: [r'void main\('],
      );
      expect(result.isError, isNot(isTrue));
      final content = result.content.first as TextContent;

      expect(content.text, contains('package:counter_app/main.dart'));
      expect(content.text, contains('void main('));
    });

    test('finds matches with glob pattern', () async {
      final result = await grep(
        packageNames: ['counter_app'],
        arguments: ['-g', '*.dart', 'class MyApp'],
      );
      expect(result.isError, isNot(isTrue));
      final content = result.content.first as TextContent;

      expect(content.text, contains('package:counter_app/main.dart'));
      expect(content.text, contains('class MyApp'));
    });

    test('finds matches in package dependencies', () async {
      final result = await grep(
        packageNames: ['flutter'],
        arguments: ['class Widget'],
      );

      expect(result.isError, isNot(isTrue));
      final content = result.content.first as TextContent;
      expect(
        content.text,
        contains('package:flutter/src/widgets/framework.dart'),
      );
    });

    test('supports case insensitive search', () async {
      final result = await grep(
        packageNames: ['counter_app'],
        arguments: ['-i', r'VOID MAIN\('],
      );
      expect(result.isError, isNot(isTrue));
      final content = result.content.first as TextContent;

      expect(content.text, contains('package:counter_app/main.dart'));
    });

    test('returns a good message when package not found', () async {
      final result = await grep(
        packageNames: ['non_existent_package'],
        arguments: ['class Widget'],
      );
      expect(result.isError, isNot(isTrue));
      final content = result.content.first as TextContent;
      expect(
        content.text,
        contains(packageNotFoundText('non_existent_package').text),
      );
    });

    test('returns a good message when no matches found', () async {
      final result = await grep(
        packageNames: ['counter_app'],
        arguments: ['non_existent_class'],
      );
      expect(result.isError, isNot(isTrue));
      final content = result.content.first as TextContent;
      expect(content.text, contains('No matches in package `counter_app`'));
    });

    test('can search outside of lib/ when searchDir is empty string', () async {
      final result = await grep(
        packageNames: ['counter_app'],
        arguments: ['name: counter_app'],
        searchDir: '',
      );
      expect(result.isError, isNot(isTrue));
      final content = result.content.first as TextContent;

      expect(content.text, contains('package-root:counter_app/pubspec.yaml'));
    });

    test('can search in specific directory', () async {
      final server = testHarness.serverConnectionPair.server!;
      final testDir = server.fileSystem.directory(
        Uri.parse(counterAppRoot.uri).resolve('grep_test/').toFilePath(),
      );
      addTearDown(() => testDir.delete(recursive: true));
      testDir.createSync(recursive: true);
      final testFile = server.fileSystem.file(
        testDir.uri.resolve('dummy_test.dart').toFilePath(),
      );
      testFile.writeAsStringSync('void main() { print("dummy test"); }');

      final result = await grep(
        packageNames: ['counter_app'],
        arguments: ['dummy test'],
        searchDir: 'grep_test', // search specifically in "grep_test"
      );
      expect(result.isError, isNot(isTrue));
      final content = result.content.first as TextContent;

      // Results outside lib use package-root:
      expect(
        content.text,
        contains('package-root:counter_app/grep_test/dummy_test.dart'),
      );
      expect(content.text, contains('dummy test'));
    });
  });

  test('Can install ripgrep', () async {
    final server = testHarness.serverConnectionPair.server!;
    final tmpDir = server.fileSystem.systemTempDirectory.createTempSync(
      'rip-grep-test',
    );
    try {
      final installPath = await server.tryInstallRipGrep(installDir: tmpDir);
      expect(installPath, isNotNull);
      final executable = server.fileSystem.file(installPath);
      expect(executable.existsSync(), isTrue);
      expect(executable.statSync().modeString(), contains('x'));
    } finally {
      tmpDir.deleteSync(recursive: true);
    }
  });
}
