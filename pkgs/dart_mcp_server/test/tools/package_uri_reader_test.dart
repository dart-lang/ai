// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp_server/src/mixins/package_uri_reader.dart';
import 'package:dart_mcp_server/src/utils/constants.dart';
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
    test('can read package: uris for the root package', () async {
      final result = await readUris([
        'package:counter_app/images/add_to_vs_code.png',
        'package:counter_app/main.dart',
        'package:counter_app/',
      ]);
      expect(
        result.content,
        containsAll([
          matchesEmbeddedTextResource(
            contains('void main('),
            'package:counter_app/main.dart',
          ),
          matchesEmbeddedBlobResource(
            isA<String>(),
            'package:counter_app/images/add_to_vs_code.png',
            'image/png',
          ),
          matchesResourceLink('package:counter_app/driver_main.dart'),
          matchesResourceLink('package:counter_app/main.dart'),
          matchesResourceLink('package:counter_app/images/'),
        ]),
      );
    });

    test('can read package: uris for other packages', () async {
      final result = await readUris(['package:flutter/material.dart']);
      expect(
        result.content,
        containsAll([
          matchesEmbeddedTextResource(
            contains('library material;'),
            'package:flutter/material.dart',
          ),
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

    test('returns an error for non-package uris', () async {
      final result = await readUris(['file:///foo/bar.dart']);
      expect(
        result.content,
        contains(
          isTextContent(
            'The URI "file:///foo/bar.dart" was not a "package:" URI.',
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
            'The package "not_a_real_package" was not found in your package config, '
            'make sure it is listed in your dependencies, or use `pub add` to '
            'add it.',
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
            'File not found: package:counter_app/not_a_real_file.dart',
          ),
        ),
      );
    });
  });
}

TypeMatcher<TextContent> isTextContent(dynamic textMatcher) =>
    isA<TextContent>().having((c) => c.text, 'text', textMatcher);

TypeMatcher<EmbeddedResource> isEmbeddedResource() =>
    isA<EmbeddedResource>().having(
      (content) => content.type,
      'type',
      equals(EmbeddedResource.expectedType),
    );

TypeMatcher<TextResourceContents> isTextResource() =>
    isA<TextResourceContents>().having(
      (resource) => resource.isText,
      'isText',
      isTrue,
    );

Matcher matchesEmbeddedTextResource(dynamic contentMatcher, dynamic uri) =>
    isEmbeddedResource().having(
      (content) => content.resource,
      'resource',
      isTextResource()
          .having((resource) => resource.text, 'text', contentMatcher)
          .having((resource) => resource.uri, 'uri', uri),
    );

TypeMatcher<BlobResourceContents> isBlobResource() =>
    isA<BlobResourceContents>().having(
      (resource) => resource.isBlob,
      'isBlob',
      isTrue,
    );

Matcher matchesEmbeddedBlobResource(
  dynamic contentMatcher,
  dynamic uri,
  dynamic mimeType,
) => isEmbeddedResource().having(
  (content) => content.resource,
  'resource',
  isBlobResource()
      .having((resource) => resource.blob, 'blob', contentMatcher)
      .having((resource) => resource.uri, 'uri', uri)
      .having((resource) => resource.mimeType, 'mimeType', mimeType),
);

TypeMatcher<ResourceLink> isResourceLink() => isA<ResourceLink>().having(
  (content) => content.type,
  'type',
  equals(ResourceLink.expectedType),
);

Matcher matchesResourceLink(String uri) =>
    isResourceLink().having((link) => link.uri, 'uri', uri);
