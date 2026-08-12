// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_mcp/client.dart';
import 'package:test/test.dart';

void main() {
  test('error codes hold the values their revision assigned', () {
    // Expected values are pinned from the schema constants: HEADER_MISMATCH,
    // MISSING_REQUIRED_CLIENT_CAPABILITY, and UNSUPPORTED_PROTOCOL_VERSION in
    // the 2026-07-28 schema, and URL_ELICITATION_REQUIRED in the 2025-11-25
    // schema.
    expect(McpErrorCodes.headerMismatch, -32020);
    expect(McpErrorCodes.missingRequiredClientCapability, -32021);
    expect(McpErrorCodes.unsupportedProtocolVersion, -32022);
    expect(McpErrorCodes.urlElicitationRequired, -32042);
  });
}
