// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_mcp/client.dart';
import 'package:test/test.dart';

import '../test_utils.dart';

void main() {
  test('protocol versions can be compared', () {
    expect(
      ProtocolVersion.latestSupported > ProtocolVersion.oldestSupported,
      true,
    );
    expect(
      ProtocolVersion.latestSupported >= ProtocolVersion.oldestSupported,
      true,
    );
    expect(
      ProtocolVersion.latestSupported < ProtocolVersion.oldestSupported,
      false,
    );
    expect(
      ProtocolVersion.latestSupported <= ProtocolVersion.oldestSupported,
      false,
    );

    expect(
      ProtocolVersion.oldestSupported > ProtocolVersion.latestSupported,
      false,
    );
    expect(
      ProtocolVersion.oldestSupported >= ProtocolVersion.latestSupported,
      false,
    );
    expect(
      ProtocolVersion.oldestSupported < ProtocolVersion.latestSupported,
      true,
    );
    expect(
      ProtocolVersion.oldestSupported <= ProtocolVersion.latestSupported,
      true,
    );

    expect(
      ProtocolVersion.latestSupported <= ProtocolVersion.latestSupported,
      true,
    );
    expect(
      ProtocolVersion.latestSupported >= ProtocolVersion.latestSupported,
      true,
    );
    expect(
      ProtocolVersion.latestSupported < ProtocolVersion.latestSupported,
      false,
    );
    expect(
      ProtocolVersion.latestSupported > ProtocolVersion.latestSupported,
      false,
    );
  });
  group('negotiation', () {
    test('client and server respect negotiated protocol version', () async {
      final environment = TestEnvironment(TestMCPClient(), TestMCPServer.new);
      final serverConnection = environment.serverConnection;
      final initializeResult = await serverConnection.initialize(
        InitializeRequest(
          protocolVersion: ProtocolVersion.oldestSupported,
          capabilities: environment.client.capabilities,
          clientInfo: environment.client.implementation,
        ),
      );
      expect(initializeResult.protocolVersion, ProtocolVersion.oldestSupported);
      expect(serverConnection.protocolVersion, ProtocolVersion.oldestSupported);
    });
  });
}
