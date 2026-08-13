// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_mcp/client.dart';
import 'package:test/test.dart';

void main() {
  test('the error codes hold the numbers 2026-07-28 assigned', () {
    expect(McpErrorCodes.headerMismatch, -32020);
    expect(McpErrorCodes.missingRequiredClientCapability, -32021);
    expect(McpErrorCodes.unsupportedProtocolVersion, -32022);
  });
}
