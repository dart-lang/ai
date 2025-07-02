// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('!windows')
library;

import 'dart:isolate';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

void main() {
  test('public arg parser library only exports lib/src/arg_parser.dart', () {
    checkDependencies('package:dart_mcp_server/arg_parser.dart', const [
      'src/arg_parser.dart',
    ]);
  });

  test('arg parser implementation only depends on package:args', () {
    checkDependencies('package:dart_mcp_server/src/arg_parser.dart', const [
      'package:args/args.dart',
    ]);
  });
}

/// Checks that [libraryUri] only has directives referencing [allowedUris].
///
/// The [allowedUris] are matched based on the exact string, not a resolved
/// URI.
void checkDependencies(String libraryUri, Iterable<String> allowedUris) {
  final parsed = parseFile(
    path: Isolate.resolvePackageUriSync(Uri.parse(libraryUri))!.path,
    featureSet: FeatureSet.fromEnableFlags2(
      sdkLanguageVersion: Version.parse('3.9.0'),
      flags: const [],
    ),
  );
  final uriDirectives = parsed.unit.directives.whereType<UriBasedDirective>();

  expect(
    uriDirectives.map((d) => d.uri.stringValue),
    unorderedEquals(allowedUris),
  );
}
