import 'dart:async';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/server.dart';
import 'package:test/test.dart';

import '../test_utils.dart';

void elicitationTests() {
  group('elicitation', () {
    test('client and server can elicit information', () async {
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
        'What is your name?',
        ObjectSchema(
          properties: {'name': StringSchema(description: 'Your name')},
          required: ['name'],
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
  TestMCPClientWithElicitationSupport({this.elicitationHandler});

  @override
  final ElicitationHandler? elicitationHandler;
}

final class TestMCPServerWithElicitationRequestSupport extends TestMCPServer
    with LoggingSupport, ElicitationRequestSupport {
  TestMCPServerWithElicitationRequestSupport(super.channel);
}
