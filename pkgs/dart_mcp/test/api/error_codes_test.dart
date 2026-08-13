// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_mcp/client.dart';
import 'package:test/test.dart';

void main() {
  test('urlElicitationRequired holds the value 2025-11-25 assigned it', () {
    // The other codes get their numbers checked on the wire in
    // streamable_http_test.dart. This one is reserved on 2026-07-28 and a
    // server must not send it, so it has no wire site to check it from.
    expect(McpErrorCodes.urlElicitationRequired, -32042);
  });
}
