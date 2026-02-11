// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp_server/src/mixins/package_uri_reader.dart';
import 'package:dart_mcp_server/src/utils/names.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../test_harness.dart';

void main() {
  late TestHarness testHarness;
  late Root counterAppRoot;

  Future<CallToolResult> readUris(List<String> uris) => testHarness.callTool(
    CallToolRequest(
      name: PackageUriSupport.readPackageUris.name,
      arguments: {
        ParameterNames.root: counterAppRoot.uri,
        ParameterNames.uris: uris,
      },
    ),
  );

  setUpAll(() async {
    testHarness = await TestHarness.start(inProcess: true);
    counterAppRoot = testHarness.rootForPath(counterAppPath);
    testHarness.mcpClient.addRoot(counterAppRoot);
  });

  group('$PackageUriSupport', () {
    test(
      'can read package: and package-root: uris for the root package',
      () async {
        final server = testHarness.serverConnectionPair.server!;
        final exampleDir = server.fileSystem.directory(
          Uri.parse(counterAppRoot.uri).resolve('example/').toFilePath(),
        );
        addTearDown(() => exampleDir.delete(recursive: true));
        exampleDir.createSync(recursive: true);
        final result = await readUris([
          'package:counter_app/images/add_to_vs_code.png',
          'package:counter_app/main.dart',
          'package:counter_app/',
          'package-root:counter_app/pubspec.yaml',
          'package-root:counter_app/example/',
        ]);
        expect(
          result.content,
          containsAll([
            isTextContent(
              '## File "package:counter_app/images/add_to_vs_code.png":\n',
            ),
            isImageContent(isA<String>(), 'image/png'),
            isTextContent('## File "package:counter_app/main.dart":\n'),
            isTextContent(contains('void main(')),
            isTextContent('## Directory "package:counter_app/":\n'),
            isTextContent(
              contains('  - File: package:counter_app/main.dart\n'),
            ),
            isTextContent(
              contains('  - Directory: package:counter_app/images/\n'),
            ),
            isTextContent(
              contains('  - File: package:counter_app/driver_main.dart\n'),
            ),
            isTextContent('## File "package-root:counter_app/pubspec.yaml":\n'),
            isTextContent(contains('name: counter_app')),
            isTextContent(
              '## Directory "package-root:counter_app/example/":\n',
            ),
          ]),
        );
      },
    );

    test('can read package: uris for other packages', () async {
      final result = await readUris(['package:flutter/material.dart']);
      expect(
        result.content,
        containsAll([
          isTextContent('## File "package:flutter/material.dart":\n'),
          isTextContent(contains('library material;')),
        ]),
      );
    });

    test('returns an error if no package_config.json is found', () async {
      final emptyPackage = d.dir('empty_dir');
      await emptyPackage.create();
      final noPackageConfigAppRoot = testHarness.rootForPath(
        emptyPackage.io.path,
      );
      testHarness.mcpClient.addRoot(noPackageConfigAppRoot);
      final result = await testHarness.callTool(
        CallToolRequest(
          name: PackageUriSupport.readPackageUris.name,
          arguments: {
            ParameterNames.root: noPackageConfigAppRoot.uri,
            ParameterNames.uris: ['package:foo/bar.dart'],
          },
        ),
        expectError: true,
      );
      expect(
        result.content,
        contains(
          isTextContent(
            'No package config found for root ${noPackageConfigAppRoot.uri}. '
            'Have you ran `pub get` in this project?',
          ),
        ),
      );
    });

    test('returns an error for non-package or package-root uris', () async {
      final result = await readUris(['file:///foo/bar.dart']);
      expect(
        result.content,
        contains(
          isTextContent(
            'The URI "file:///foo/bar.dart" was not a "package:" or "package-root:" URI.',
          ),
        ),
      );
    });

    test('returns an error for unknown packages', () async {
      final result = await readUris(['package:not_a_real_package/foo.dart']);
      expect(
        result.content,
        contains(
          isTextContent(
            'The package "not_a_real_package" was not found in your package '
            'config, make sure it is listed in your dependencies, or use '
            '`pub add` to add it.',
          ),
        ),
      );
    });

    test(
      'returns an error for uris that try to escape the package root',
      () async {
        final result = await readUris(['package:counter_app/../main.dart']);
        expect(
          result.content,
          contains(
            isTextContent(
              // This actually comes from package:package_config, so it doesn't
              // match the error we would throw.
              contains(
                'The package "main.dart" was not found in your package config',
              ),
            ),
          ),
        );
      },
    );

    test('returns an error for files that are not found', () async {
      final result = await readUris([
        'package:counter_app/not_a_real_file.dart',
      ]);
      expect(
        result.content,
        contains(
          isTextContent(
            '## File not found: "package:counter_app/not_a_real_file.dart":\n',
          ),
        ),
      );
    });
  });
}

TypeMatcher<TextContent> isTextContent(dynamic textMatcher) =>
    isA<TextContent>().having((c) => c.text, 'text', textMatcher);

TypeMatcher<ImageContent> isImageContent(
  Matcher contentMatcher,
  dynamic mimeType,
) => isA<ImageContent>()
    .having((content) => content.data, 'blob', contentMatcher)
    .having((content) => content.mimeType, 'mimeType', mimeType);
