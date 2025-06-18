// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import 'test_harness.dart';

void main() {
  group('--log-file', () {
    late d.FileDescriptor logDescriptor;
    late TestHarness testHarness;

    setUp(() async {
      logDescriptor = d.file('log.txt');
      testHarness = await TestHarness.start(
        inProcess: false,
        cliArgs: ['--log-file', logDescriptor.io.path],
      );
    });

    test('logs traffic to a file', () async {
      // It may take a bit for all the lines to show up in the log.
      await doWithRetries(
        () async => expect(
          await File(logDescriptor.io.path).readAsLines(),
          containsAll([
            allOf(startsWith('<<<'), contains('"method":"initialize"')),
            allOf(startsWith('>>>'), contains('"serverInfo"')),
            allOf(startsWith('<<<'), contains('"notifications/initialized"')),
          ]),
        ),
      );

      // Ensure the file handle is released before the file is cleaned up.
      await testHarness.serverConnectionPair.serverConnection.shutdown();

      // Wait for the process to release the file.
      await doWithRetries(() => File(logDescriptor.io.path).delete());
    });
  });
}

/// Performs [action] up to [maxRetries] times, backing off an extra 50ms
/// between each attempt.
FutureOr<T> doWithRetries<T>(
  FutureOr<T> Function() action, {
  int maxRetries = 5,
}) async {
  var count = 0;
  while (true) {
    try {
      return await action();
    } catch (_) {
      if (count == maxRetries) {
        rethrow;
      }
    }
    count++;
    await Future<void>.delayed(Duration(milliseconds: 50 * count));
  }
}
