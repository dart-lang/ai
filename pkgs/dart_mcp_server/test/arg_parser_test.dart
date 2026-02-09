// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('!windows')
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:package_config/package_config.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

void main() async {
  final packageConfig = (await findPackageConfig(Directory.current))!;

  test(
    'public arg parser library depends on package:args and internal utils',
    () {
      checkTransitiveDependencies(
        packageConfig,
        Uri.parse('package:dart_mcp_server/arg_parser.dart'),
        const ['args', 'dart_mcp_server'],
      );
    },
  );

  test('checkTransitiveDependencies', () {
    expect(
      () => checkTransitiveDependencies(
        packageConfig,
        Uri.parse('package:test/test.dart'),
        const ['test_api'],
      ),
      throwsA(
        isA<TestFailure>().having(
          (e) => e.message,
          'message',
          allOf(
            contains(
              'Library package:test/test.dart references disallowed packages',
            ),
            contains('test_core'),
          ),
        ),
      ),
    );
  });
}

/// Checks that [libraryUri] and all its transitive dependencies only have
/// directives referencing [allowedPackages].
void checkTransitiveDependencies(
  PackageConfig packageConfig,
  Uri libraryUri,
  Iterable<String> allowedPackages, {
  Set<Uri>? visited,
}) {
  visited ??= {};
  if (!visited.add(libraryUri)) {
    return;
  }
  final languageVersion =
      packageConfig[libraryUri.pathSegments.first]!.languageVersion!;
  final parsed = parseFile(
    path: packageConfig.resolve(libraryUri)!.path,
    featureSet: FeatureSet.fromEnableFlags2(
      sdkLanguageVersion: Version(
        languageVersion.major,
        languageVersion.minor,
        0,
      ),
      flags: const [],
    ),
  );
  final uriDirectives = parsed.unit.directives.whereType<UriBasedDirective>();
  final resolvedUris = uriDirectives
      .map((d) => d.uri.stringValue!)
      .where((uriString) => !uriString.startsWith('dart:'))
      .map((uriString) => libraryUri.resolve(uriString));
  final referencedPackages = {
    for (final uri in resolvedUris) uri.pathSegments.first,
  };

  expect(
    allowedPackages,
    containsAll(referencedPackages),
    reason:
        'Library $libraryUri references disallowed packages '
        '$referencedPackages',
  );
  for (final uri in resolvedUris) {
    checkTransitiveDependencies(
      packageConfig,
      uri,
      allowedPackages,
      visited: visited,
    );
  }
}
