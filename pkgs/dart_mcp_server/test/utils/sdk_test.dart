// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'package:dart_mcp_server/src/utils/sdk.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  group('Sdk', () {
    test('find respects DART_ROOT', () async {
      final fakeSdkDir = d.dir('sdk', [
        // We use the version file existance to validate that it is an SDK.
        d.file('version', ''),
      ]);
      await fakeSdkDir.create();
      final sdk = Sdk.find(environment: {'DART_ROOT': fakeSdkDir.io.path});
      expect(sdk.dartSdkPath, fakeSdkDir.io.path);
    });

    test('find throws if DART_ROOT is invalid', () {
      expect(
        () => Sdk.find(environment: {'DART_ROOT': '/non/existent/path'}),
        throwsArgumentError,
      );
    });

    test('find uses Platform.resolvedExecutable if DART_ROOT is not set', () {
      final realSdkPath = p.dirname(p.dirname(Platform.resolvedExecutable));
      final sdk = Sdk.find(environment: const {});
      expect(sdk.dartSdkPath, realSdkPath);
    });
  });
}
