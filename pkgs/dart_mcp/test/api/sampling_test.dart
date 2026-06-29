// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:checks/checks.dart';
import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/src/client/client.dart';
import 'package:test/test.dart';

import '../test_utils.dart';

void main() {
  test('server can request LLM messages from the client', () async {
    final environment = TestEnvironment(
      SamplingTestMCPClient(),
      TestMCPServer.new,
    );
    await environment.initializeServer();
    final server = environment.server;
    check(server.clientCapabilities.sampling).isNotNull();

    final client = environment.client;
    final expectedResult =
        client.nextResult = CreateMessageResult(
          role: Role.assistant,
          content: TextContent(text: 'Hello'),
          model: 'fakeModel',
        );

    final result = await server.createMessage(
      CreateMessageRequest(messages: [], maxTokens: 100),
    );
    check(
      result as Map<String, Object?>,
    ).deepEquals(expectedResult as Map<String, Object?>);
  });
}

final class SamplingTestMCPClient extends TestMCPClient with SamplingSupport {
  /// Must be assign prior to sending a [CreateMessageRequest], and will be used
  /// as the response to the next request.
  CreateMessageResult? nextResult;

  @override
  FutureOr<CreateMessageResult> handleCreateMessage(
    CreateMessageRequest request,
    Implementation serverInfo,
  ) {
    if (nextResult case final result?) {
      nextResult = null;
      return result;
    } else {
      throw StateError('Must assign `nextResult` before issuing requests');
    }
  }
}
