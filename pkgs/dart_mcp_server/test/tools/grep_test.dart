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
    bool expectError = false,
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
      expectError: expectError,
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
        arguments: ['-e', r'void main\('],
      );
      expect(result.isError, isNot(isTrue));
      final content = result.content.first as TextContent;

      expect(content.text, contains('package:counter_app/main.dart'));
      expect(content.text, contains('void main('));
    });

    test('finds matches with glob pattern', () async {
      final result = await grep(
        packageNames: ['counter_app'],
        arguments: ['-g', '*.dart', '-e', 'class MyApp'],
      );
      expect(result.isError, isNot(isTrue));
      final content = result.content.first as TextContent;

      expect(content.text, contains('package:counter_app/main.dart'));
      expect(content.text, contains('class MyApp'));
    });

    test('finds matches in package dependencies', () async {
      final result = await grep(
        packageNames: ['flutter'],
        arguments: ['-e', 'class Widget'],
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
        arguments: ['-i', '-e', r'VOID MAIN\('],
      );
      expect(result.isError, isNot(isTrue));
      final content = result.content.first as TextContent;

      expect(content.text, contains('package:counter_app/main.dart'));
    });

    test('returns a good message when package not found', () async {
      final result = await grep(
        packageNames: ['non_existent_package'],
        arguments: ['-e', 'class Widget'],
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
        arguments: ['-e', 'non_existent_class'],
      );
      expect(result.isError, isNot(isTrue));
      final content = result.content.first as TextContent;
      expect(content.text, contains('No matches in package `counter_app`'));
    });

    test('can search outside of lib/ when searchDir is empty string', () async {
      final result = await grep(
        packageNames: ['counter_app'],
        arguments: ['-e', 'name: counter_app'],
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
        arguments: ['-e', 'dummy test'],
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

    test('refuses to search outside package root', () async {
      final result = await grep(
        packageNames: ['counter_app'],
        arguments: ['-e', 'dummy test'],
        searchDir: '../', // try to escape the root
      );
      expect(result.isError, isNot(isTrue)); // we return content with the error
      final content = result.content.first as TextContent;

      expect(
        content.text,
        contains('attempted to escape the root of package `counter_app`'),
      );
    });

    test('refuses to search outside package root via symlink', () async {
      final server = testHarness.serverConnectionPair.server!;
      final externalDir = server.fileSystem.systemTempDirectory.createTempSync(
        'grep_external_',
      );
      addTearDown(() => externalDir.deleteSync(recursive: true));
      externalDir
          .childFile('outside.dart')
          .writeAsStringSync('const externalMarker = 1;\n');

      final link = server.fileSystem.link(
        Uri.parse(counterAppRoot.uri).resolve('external_link').toFilePath(),
      );
      addTearDown(() {
        if (server.fileSystem.isLinkSync(link.path)) {
          link.deleteSync();
        }
      });
      link.createSync(externalDir.path);

      final result = await grep(
        packageNames: ['counter_app'],
        arguments: ['-e', 'externalMarker'],
        searchDir: 'external_link',
      );
      expect(result.isError, isNot(isTrue));
      final content = result.content.first as TextContent;
      expect(
        content.text,
        contains('attempted to escape the root of package `counter_app`'),
      );
      expect(content.text, isNot(contains('externalMarker')));
    });

    test('supports --regexp= and hyphen-prefixed patterns', () async {
      final result = await grep(
        packageNames: ['counter_app'],
        arguments: ['--regexp=void main'],
      );
      expect(result.isError, isNot(isTrue));
      expect(
        (result.content.first as TextContent).text,
        contains('package:counter_app/main.dart'),
      );

      final hyphenPatternResult = await grep(
        packageNames: ['counter_app'],
        arguments: ['-e', '-non-existent-flag-like-pattern'],
      );
      expect(hyphenPatternResult.isError, isNot(isTrue));
      expect(
        (hyphenPatternResult.content.first as TextContent).text,
        contains('No matches in package `counter_app`'),
      );
    });
  });

  test('rejects arbitrary ripgrep flags', () async {
    final result = await grep(
      packageNames: ['counter_app'],
      arguments: ['--pre', 'echo', '-e', 'void main'],
      expectError: true,
    );
    expect(result.isError, isTrue);
    final content = result.content.first as TextContent;
    expect(
      content.text,
      contains(
        'Refusing to run ripgrep: the following arguments are not permitted: '
        '--pre, echo',
      ),
    );
  });

  test('requires at least one pattern flag', () async {
    for (final args in [
      ['-i'],
      ['-v', '--hidden'],
    ]) {
      final result = await grep(
        packageNames: ['counter_app'],
        arguments: args,
        expectError: true,
      );
      expect(result.isError, isTrue);
      expect(
        (result.content.first as TextContent).text,
        contains('at least one search pattern must be provided'),
      );
    }

    final danglingFlagResult = await grep(
      packageNames: ['counter_app'],
      arguments: ['-e'],
      expectError: true,
    );
    expect(danglingFlagResult.isError, isTrue);
    expect(
      (danglingFlagResult.content.first as TextContent).text,
      contains('the following arguments are not permitted: -e'),
    );
  });

  test('rejects boolean flags with inline values', () async {
    final result = await grep(
      packageNames: ['counter_app'],
      arguments: ['--hidden=true', '-e', 'void main'],
      expectError: true,
    );
    expect(result.isError, isTrue);
    expect(
      (result.content.first as TextContent).text,
      contains('the following arguments are not permitted: --hidden=true'),
    );
  });

  test('rejects NUL characters in arguments and searchDir', () async {
    final argResult = await grep(
      packageNames: ['counter_app'],
      arguments: ['-e', 'void main\x00'],
      expectError: true,
    );
    expect(argResult.isError, isTrue);
    expect(
      (argResult.content.first as TextContent).text,
      contains('the following arguments are not permitted'),
    );

    final dirResult = await grep(
      packageNames: ['counter_app'],
      arguments: ['-e', 'void main'],
      searchDir: 'lib\x00',
    );
    expect(dirResult.isError, isNot(isTrue));
    expect(
      (dirResult.content.first as TextContent).text,
      contains('attempted to escape the root of package `counter_app`'),
    );
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
