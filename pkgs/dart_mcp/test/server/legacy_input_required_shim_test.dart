// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:async/async.dart';
import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/server.dart';
import 'package:json_rpc_2/error_code.dart' as error_code;
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

import '../test_utils.dart';

void main() {
  test('stops after the configured input-required rounds', () async {
    var elicitations = 0;
    final environment = TestEnvironment(
      _FormClient(
        elicitationHandler: (request, connection) {
          elicitations++;
          return ElicitResult(action: ElicitationAction.accept);
        },
      ),
      (channel) => _CappedRoundsServer(channel, maxInputRequiredRounds: 1),
    );
    await environment.initializeServer();

    await expectLater(
      environment.serverConnection.callTool(CallToolRequest(name: 'ask')),
      throwsA(
        isA<RpcException>()
            .having((e) => e.code, 'code', error_code.INTERNAL_ERROR)
            .having(
              (e) => e.message,
              'message',
              contains('exceeded the maximum'),
            ),
      ),
    );
    expect(environment.server.handlerCalls, 2);
    expect(elicitations, 1);
  });

  test('a retry limit below one is a RangeError', () {
    expect(
      () => _CappedRoundsServer(
        StreamChannel.withCloseGuarantee(
          const Stream<Map<String, Object?>>.empty(),
          NullStreamSink<Map<String, Object?>>(),
        ),
        maxInputRequiredRounds: 0,
      ),
      throwsA(
        isA<RangeError>().having(
          (e) => e.name,
          'name',
          'maxInputRequiredRounds',
        ),
      ),
    );
  });
}

final class _FormClient extends TestMCPClient with ElicitationFormSupport {
  _FormClient({required this.elicitationHandler});

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

final class _CappedRoundsServer extends MCPServer with ToolsSupport {
  _CappedRoundsServer(super.channel, {super.maxInputRequiredRounds = 1})
    : super.fromStreamChannel(
        implementation: Implementation(name: 'test server', version: '0.1.0'),
      );

  int handlerCalls = 0;

  @override
  FutureOr<void> initialize(MCPServerInitialization initialization) {
    registerTool(Tool(name: 'ask', inputSchema: ObjectSchema()), (_) {
      handlerCalls++;
      return InputRequiredResult(
        inputRequests: {
          'answer': InputRequest.elicit(
            ElicitRequest.form(
              message: 'need input',
              requestedSchema: ObjectSchema(),
            ),
          ),
        },
      );
    });
    return super.initialize(initialization);
  }
}
