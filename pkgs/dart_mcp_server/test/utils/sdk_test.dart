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

    group('flutterExecutablePath error', () {
      Future<String> fakeDartSdk() async {
        final dir = d.dir('dart-sdk', [d.file('version', '')]);
        await dir.create();
        return dir.io.path;
      }

      void expectMessage(Sdk sdk, List<Matcher> parts) {
        expect(
          () => sdk.flutterExecutablePath,
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              allOf([startsWith('Flutter SDK location unknown.'), ...parts]),
            ),
          ),
        );
      }

      test('names the Dart SDK and the DART_ROOT variable', () async {
        final path = await fakeDartSdk();
        final sdk = Sdk.find(environment: {'DART_ROOT': path});
        expectMessage(sdk, [
          contains('Dart SDK at $path'),
          contains('the DART_ROOT environment variable'),
        ]);
      });

      test('names the DART_SDK variable', () async {
        final path = await fakeDartSdk();
        final sdk = Sdk.find(environment: {'DART_SDK': path});
        expectMessage(sdk, [contains('the DART_SDK environment variable')]);
      });

      test('names the --dart-sdk argument', () async {
        final path = await fakeDartSdk();
        final sdk = Sdk.find(dartSdkPath: path, environment: const {});
        expectMessage(sdk, [contains('the --dart-sdk argument')]);
      });

      test('records the running executable when nothing is configured', () {
        final sdk = Sdk.find(environment: const {});
        expect(sdk.dartSdkSource, contains(Platform.resolvedExecutable));
      });

      test('still explains the fix when nothing is known', () {
        expectMessage(Sdk(), [
          isNot(contains('Dart SDK at')),
          contains('FLUTTER_SDK environment variable'),
          contains('--flutter-sdk'),
        ]);
      });
    });
  });
}
