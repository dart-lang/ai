// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:skills/src/core/version.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('version in version.dart matches pubspec.yaml', () {
    final pubspecFile = File('pubspec.yaml');
    expect(pubspecFile.existsSync(), isTrue, reason: 'pubspec.yaml not found');
    final pubspecContent = pubspecFile.readAsStringSync();
    final pubspecYaml = loadYaml(pubspecContent) as YamlMap;
    final pubspecVersion = pubspecYaml['version'] as String;

    expect(
      version,
      equals(pubspecVersion),
      reason:
          'The version in lib/src/core/version.dart does not match the version in pubspec.yaml',
    );
  });
}
