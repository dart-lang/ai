// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/server.dart';
import 'package:test/test.dart';

import '../test_utils.dart';

void main() {
  group('elicitation', () {
    test('server can elicit information from client', () async {
      final elicitationCompleter = Completer<ElicitResult>();
      final environment = TestEnvironment(
        TestMCPClientWithElicitationSupport(
          elicitationHandler: (request) {
            return elicitationCompleter.future;
          },
        ),
        TestMCPServerWithElicitationRequestSupport.new,
      );
      final server = environment.server;
      unawaited(server.initialized);
      await environment.serverConnection.initialize(
        InitializeRequest(
          protocolVersion: ProtocolVersion.latestSupported,
          capabilities: environment.client.capabilities,
          clientInfo: environment.client.implementation,
        ),
      );

      final elicitationRequest = server.elicit(
        ElicitRequest(
          message: 'What is your name?',
          requestedSchema: ObjectSchema(
            properties: {'name': StringSchema(description: 'Your name')},
            required: ['name'],
          ),
        ),
      );

      elicitationCompleter.complete(
        ElicitResult(
          action: ElicitationAction.accept,
          content: {'name': 'John Doe'},
        ),
      );

      final result = await elicitationRequest;
      expect(result.action, ElicitationAction.accept);
      expect(result.content, {'name': 'John Doe'});
    });
  });
}

final class TestMCPClientWithElicitationSupport extends TestMCPClient
    with ElicitationSupport {
  TestMCPClientWithElicitationSupport({required this.elicitationHandler});

  FutureOr<ElicitResult> Function(ElicitRequest request) elicitationHandler;

  @override
  FutureOr<ElicitResult> handleElicitation(ElicitRequest request) {
    return elicitationHandler(request);
  }
}

base class TestMCPServerWithElicitationRequestSupport extends TestMCPServer
    with LoggingSupport, ElicitationRequestSupport {
  TestMCPServerWithElicitationRequestSupport(super.channel);
}
