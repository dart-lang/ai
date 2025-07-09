// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_mcp/server.dart';
import 'package:test/test.dart';

void main() {
  test('null instructions', () async {
    final result = InitializeResult(
      protocolVersion: ProtocolVersion.latestSupported,
      serverCapabilities: ServerCapabilities(),
      serverInfo: Implementation(name: 'name', version: 'version'),
    );

    final map = result as Map<String, Object?>;
    expect(map.containsKey('instructions'), isFalse);
  });

  test('nonnull instructions', () async {
    final result = InitializeResult(
      protocolVersion: ProtocolVersion.latestSupported,
      serverCapabilities: ServerCapabilities(),
      serverInfo: Implementation(name: 'name', version: 'version'),
      instructions: 'foo',
    );

    final map = result as Map<String, Object?>;
    expect(map['instructions'], equals('foo'));
  });
}
