// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/server.dart';
import 'package:json_rpc_2/error_code.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  test('client and server can communicate', () async {
    var environment = TestEnvironment(TestMCPClient(), TestMCPServer.new);
    var initializeResult = await environment.initializeServer();

    expect(initializeResult.capabilities, isEmpty);
    expect(initializeResult.instructions, environment.server.instructions);
    expect(initializeResult.protocolVersion, protocolVersion);

    expect(
      environment.serverConnection.listTools(ListToolsRequest()),
      throwsA(
        isA<RpcException>().having((e) => e.code, 'code', METHOD_NOT_FOUND),
      ),
      reason: 'Calling unsupported methods should throw',
    );
  });
}
