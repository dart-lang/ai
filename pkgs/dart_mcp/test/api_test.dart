// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_mcp/client.dart';
import 'package:test/test.dart';

void main() {
  test('protocol versions can be compared', () {
    expect(
      ProtocolVersion.latest > ProtocolVersion.oldestSupportedVersion,
      true,
    );
    expect(
      ProtocolVersion.latest >= ProtocolVersion.oldestSupportedVersion,
      true,
    );
    expect(
      ProtocolVersion.latest < ProtocolVersion.oldestSupportedVersion,
      false,
    );
    expect(
      ProtocolVersion.latest <= ProtocolVersion.oldestSupportedVersion,
      false,
    );

    expect(
      ProtocolVersion.oldestSupportedVersion > ProtocolVersion.latest,
      false,
    );
    expect(
      ProtocolVersion.oldestSupportedVersion >= ProtocolVersion.latest,
      false,
    );
    expect(
      ProtocolVersion.oldestSupportedVersion < ProtocolVersion.latest,
      true,
    );
    expect(
      ProtocolVersion.oldestSupportedVersion <= ProtocolVersion.latest,
      true,
    );

    expect(ProtocolVersion.latest <= ProtocolVersion.latest, true);
    expect(ProtocolVersion.latest >= ProtocolVersion.latest, true);
    expect(ProtocolVersion.latest < ProtocolVersion.latest, false);
    expect(ProtocolVersion.latest > ProtocolVersion.latest, false);
  });
}
