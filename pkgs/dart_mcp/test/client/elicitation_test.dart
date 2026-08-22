// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/src/utils/constants.dart';
import 'package:json_rpc_2/error_code.dart' as error_code;
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:stream_channel/stream_channel.dart';
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
              // The number the 2025-11-25 revision assigns, written out
              // so that the recognition below is not comparing the constant
              // to itself.
              throw RpcException(
                -32042,
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

    test('rethrows when the error data is not a url elicitation', () async {
      final environment = TestEnvironment(
        TestMCPClientWithElicitationUrlSupport(
          elicitationHandler: (request, connection) async {
            fail(
              'should not hand a ${request.rawMode} request to the url '
              'handler',
            );
          },
        ),
        TestMCPServerWithTools.new,
      );

      await environment.initializeServer();
      final server = environment.server;

      // A payload with no mode reads as form, and one naming a mode this
      // version has no value for is not a url request either.
      final payloads = [
        <String, Object?>{Keys.message: 'Fill this in'},
        <String, Object?>{Keys.mode: 'voice', Keys.message: 'Fill this in'},
        // The error is whatever the peer sent, so the mode need not be a
        // string at all. Reading it must not lose the error it came with.
        <String, Object?>{Keys.mode: 42, Keys.message: 'Fill this in'},
      ];
      for (var i = 0; i < payloads.length; i++) {
        final data = payloads[i];
        server.registerTool(
          Tool(name: 'test_tool_$i', inputSchema: ObjectSchema()),
          (request) =>
              throw RpcException(
                McpErrorCodes.urlElicitationRequired,
                'Url required',
                data: data as ElicitRequest,
              ),
        );

        await expectLater(
          () => environment.serverConnection.callTool(
            CallToolRequest(name: 'test_tool_$i'),
          ),
          throwsA(
            isA<RpcException>().having(
              (e) => e.code,
              'code',
              McpErrorCodes.urlElicitationRequired,
            ),
          ),
        );
      }
    });

    test('rethrows when the error data is not a map', () async {
      final clientController = StreamController<Map<String, Object?>>();
      final serverController = StreamController<Map<String, Object?>>();
      final client = TestMCPClientWithElicitationUrlSupport(
        elicitationHandler: (request, connection) async {
          fail('should not elicit without an elicitation request');
        },
      );
      addTearDown(client.shutdown);
      final connection = client.connectServer(
        StreamChannel.withGuarantees(
          clientController.stream,
          serverController.sink,
        ),
      );
      // Answer like a non-Dart server which attaches something other than an
      // elicitation request as the error data.
      serverController.stream.listen((request) {
        clientController.add({
          Keys.jsonrpc: '2.0',
          Keys.id: request[Keys.id],
          Keys.error: {
            Keys.code: McpErrorCodes.urlElicitationRequired,
            Keys.message: 'Url required',
            Keys.data: 'not a map',
          },
        });
      });

      await expectLater(
        () => connection.callTool(CallToolRequest(name: 'test_tool')),
        throwsA(
          isA<RpcException>()
              .having(
                (e) => e.code,
                'code',
                McpErrorCodes.urlElicitationRequired,
              )
              .having((e) => e.data, 'data', 'not a map'),
        ),
      );
    });
  });

  group('elicitation mode mismatches', () {
    // `sendRequest` skips the check `elicit` runs, so a request from a server
    // without one of its own reaches the client guard.
    test('answers a form request with invalid params', () async {
      final environment = TestEnvironment(
        TestMCPClientWithElicitationUrlSupport(
          elicitationHandler:
              (request, connection) =>
                  fail('the client should not be asked to handle a form'),
        ),
        TestMCPServer.new,
      );
      final server = environment.server;
      await environment.initializeServer();

      await expectLater(
        server.sendRequest<ElicitResult>(
          ElicitRequest.methodName,
          ElicitRequest.form(
            message: 'What is your name?',
            requestedSchema: ObjectSchema(),
          ),
        ),
        throwsA(
          isA<RpcException>()
              .having((e) => e.code, 'code', error_code.INVALID_PARAMS)
              .having(
                (e) => e.message,
                'message',
                contains('elicitation.form'),
              ),
        ),
      );
    });

    test('a request with no mode reaches the form handler', () async {
      final environment = TestEnvironment(
        TestMCPClientWithElicitationFormSupport(
          elicitationHandler:
              (request, connection) =>
                  ElicitResult(action: ElicitationAction.accept),
        ),
        TestMCPServer.new,
      );
      final server = environment.server;
      await environment.initializeServer();

      final result = await server.sendRequest<ElicitResult>(
        ElicitRequest.methodName,
        <String, Object?>{Keys.message: 'need input'} as ElicitRequest,
      );
      expect(result.action, ElicitationAction.accept);
    });

    test('rawMode is the value the sender put on the wire', () {
      final request =
          <String, Object?>{Keys.message: 'hi', Keys.mode: 'voice'}
              as ElicitRequest;

      expect(request.rawMode, 'voice');
      expect(() => request.mode, throwsStateError);
    });

    test('rawMode is null with no mode field', () {
      final request = <String, Object?>{Keys.message: 'hi'} as ElicitRequest;

      expect(request.rawMode, isNull);
      expect(request.mode, ElicitationMode.form);
    });

    test('refuses an unknown mode', () async {
      final environment = TestEnvironment(
        TestMCPClientWithElicitationFormSupport(
          elicitationHandler:
              (request, connection) => fail(
                'the client should not be asked to handle an unknown mode',
              ),
        ),
        TestMCPServer.new,
      );
      final server = environment.server;
      await environment.initializeServer();

      await expectLater(
        server.sendRequest<ElicitResult>(
          ElicitRequest.methodName,
          <String, Object?>{Keys.mode: 'voice', Keys.message: 'pick one'}
              as ElicitRequest,
        ),
        throwsA(
          isA<RpcException>()
              .having((e) => e.code, 'code', error_code.INVALID_PARAMS)
              .having((e) => e.message, 'message', contains('voice')),
        ),
      );

      // A peer can put anything in that field.
      await expectLater(
        server.sendRequest<ElicitResult>(
          ElicitRequest.methodName,
          <String, Object?>{Keys.mode: 42, Keys.message: 'pick one'}
              as ElicitRequest,
        ),
        throwsA(
          isA<RpcException>().having(
            (e) => e.code,
            'code',
            error_code.INVALID_PARAMS,
          ),
        ),
      );
    });

    test('a url client answers an unknown mode the same way', () async {
      final environment = TestEnvironment(
        TestMCPClientWithElicitationUrlSupport(
          elicitationHandler:
              (request, connection) => fail(
                'the client should not be asked to handle an unknown mode',
              ),
        ),
        TestMCPServer.new,
      );
      final server = environment.server;
      await environment.initializeServer();

      await expectLater(
        server.sendRequest<ElicitResult>(
          ElicitRequest.methodName,
          <String, Object?>{Keys.mode: 'voice', Keys.message: 'pick one'}
              as ElicitRequest,
        ),
        throwsA(
          isA<RpcException>().having(
            (e) => e.code,
            'code',
            error_code.INVALID_PARAMS,
          ),
        ),
      );
    });

    test('answers a url request with invalid params', () async {
      final environment = TestEnvironment(
        TestMCPClientWithElicitationFormSupport(
          elicitationHandler:
              (request, connection) =>
                  fail('the client should not be asked to handle a url'),
        ),
        TestMCPServer.new,
      );
      final server = environment.server;
      await environment.initializeServer();

      await expectLater(
        server.sendRequest<ElicitResult>(
          ElicitRequest.methodName,
          ElicitRequest.url(
            message: 'Grant access',
            url: 'https://example.com',
            elicitationId: '1',
          ),
        ),
        throwsA(
          isA<RpcException>()
              .having((e) => e.code, 'code', error_code.INVALID_PARAMS)
              .having((e) => e.message, 'message', contains('elicitation.url')),
        ),
      );
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
