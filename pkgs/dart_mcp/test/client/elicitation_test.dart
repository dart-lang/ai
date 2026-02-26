// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/server.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:test/test.dart';

import '../test_utils.dart';

void main() {
  group('ElicitationFormSupport', () {
    test('server can elicit information from client', () async {
      final environment = TestEnvironment(
        TestMCPClientWithElicitationFormSupport(
          elicitationHandler: (request, connection) {
            assert(request.mode == ElicitationMode.form);
            return ElicitResult(
              action: ElicitationAction.accept,
              content: {'name': 'John Doe'},
            );
          },
        ),
        TestMCPServerWithElicitationRequestSupport.new,
      );
      final server = environment.server;
      await environment.initializeServer();

      final result = await server.elicit(
        ElicitRequest.form(
          message: 'What is your name?',
          requestedSchema: ObjectSchema(
            properties: {'name': StringSchema(description: 'Your name')},
            required: ['name'],
          ),
        ),
      );
      expect(result.action, ElicitationAction.accept);
      expect(result.content, {'name': 'John Doe'});
    });
  });

  group('ElicitationUrlSupport', () {
    test(
      'autoHandleUrlElicitationRequired performs elicitation and retries tool',
      () async {
        late final TestMCPServerWithTools server;
        final environment = TestEnvironment(
          TestMCPClientWithElicitationUrlSupport(
            elicitationHandler: (request, connection) {
              assert(request.mode == ElicitationMode.url);
              // Simulate the user visiting the URL and completing the
              // elicitation after a short delay, this happens out of band
              // and only the server knows when.
              Future.delayed(
                const Duration(milliseconds: 10),
                () => server.fakeUserCompletedUrlElicitation(
                  request.elicitationId!,
                ),
              );

              // Simulate the user/client accepting the elicitation, note
              // that this happens before the user has actually completed the
              // elicitation.
              return ElicitResult(action: ElicitationAction.accept);
            },
          ),
          (channel) => server = TestMCPServerWithTools(channel),
        );

        await environment.initializeServer();

        server.registerTool(
          Tool(name: 'test_tool', inputSchema: ObjectSchema()),
          (request) {
            if (!server.userHasCompletedUrlElicitation) {
              throw RpcException(
                McpErrorCodes.urlElicitationRequired,
                'Url required',
                data: ElicitRequest.url(
                  message: 'Check out this url',
                  url: 'https://example.com',
                  elicitationId: '123',
                ),
              );
            }
            return CallToolResult(content: [TextContent(text: 'success')]);
          },
        );

        expect(server.userHasCompletedUrlElicitation, false);
        final result = await environment.serverConnection.callTool(
          CallToolRequest(name: 'test_tool'),
        );

        expect(server.userHasCompletedUrlElicitation, true);
        expect((result.content.first as TextContent).text, 'success');
      },
    );

    test('does not retry if elicitation is declined', () async {
      final environment = TestEnvironment(
        TestMCPClientWithElicitationUrlSupport(
          elicitationHandler: (request, connection) async {
            assert(request.mode == ElicitationMode.url);
            return ElicitResult(action: ElicitationAction.decline);
          },
        ),
        TestMCPServerWithTools.new,
      );

      await environment.initializeServer();
      final server = environment.server;

      var toolCallCount = 0;
      server.registerTool(
        Tool(name: 'test_tool', inputSchema: ObjectSchema()),
        (request) {
          toolCallCount++;
          throw RpcException(
            McpErrorCodes.urlElicitationRequired,
            'Url required',
            data: ElicitRequest.url(
              message: 'Check out this url',
              url: 'https://example.com',
              elicitationId: '123',
            ),
          );
        },
      );

      await expectLater(
        () => environment.serverConnection.callTool(
          CallToolRequest(name: 'test_tool'),
        ),
        throwsA(
          isA<RpcException>().having(
            (e) => e.code,
            'code',
            McpErrorCodes.urlElicitationRequired,
          ),
        ),
      );

      expect(toolCallCount, 1);
    });
  });
}

final class TestMCPClientWithElicitationFormSupport extends TestMCPClient
    with ElicitationFormSupport {
  TestMCPClientWithElicitationFormSupport({required this.elicitationHandler});

  FutureOr<ElicitResult> Function(
    ElicitRequest request,
    ServerConnection connection,
  )
  elicitationHandler;

  @override
  FutureOr<ElicitResult> handleElicitation(
    ElicitRequest request,
    ServerConnection connection,
  ) {
    return elicitationHandler(request, connection);
  }
}

final class TestMCPClientWithElicitationUrlSupport extends TestMCPClient
    with ElicitationUrlSupport {
  TestMCPClientWithElicitationUrlSupport({required this.elicitationHandler});

  FutureOr<ElicitResult> Function(
    ElicitRequest request,
    ServerConnection connection,
  )
  elicitationHandler;

  @override
  FutureOr<ElicitResult> handleElicitation(
    ElicitRequest request,
    ServerConnection connection,
  ) {
    return elicitationHandler(request, connection);
  }
}

base class TestMCPServerWithElicitationRequestSupport extends TestMCPServer
    with LoggingSupport, ElicitationRequestSupport {
  TestMCPServerWithElicitationRequestSupport(super.channel);
}

base class TestMCPServerWithTools extends TestMCPServer
    with ToolsSupport, LoggingSupport, ElicitationRequestSupport {
  bool userHasCompletedUrlElicitation = false;

  TestMCPServerWithTools(super.channel);

  void fakeUserCompletedUrlElicitation(String elicitationId) {
    userHasCompletedUrlElicitation = true;
    notifyElicitationComplete(
      ElicitationCompleteNotification(elicitationId: elicitationId),
    );
  }
}
