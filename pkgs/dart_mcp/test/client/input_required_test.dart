// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/client.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

void main() {
  test('dispatches each input request and retries the tool call', () async {
    final client =
        _InputClient()
          ..addRoot(Root(uri: 'file:///workspace', name: 'workspace'));
    final harness = _WireHarness(client, (request, requestNumber) {
      if (requestNumber == 1) {
        return {
          'resultType': 'input_required',
          'inputRequests': {
            'form': {
              'method': 'elicitation/create',
              'params': {
                'mode': 'form',
                'message': 'Enter a value',
                'requestedSchema': {
                  'type': 'object',
                  'properties': <String, Object?>{},
                },
              },
            },
            'sample': {
              'method': 'sampling/createMessage',
              'params': {'messages': <Object?>[], 'maxTokens': 1},
            },
            'roots': {'method': 'roots/list', 'params': <String, Object?>{}},
          },
          'requestState': 'opaque-state',
        };
      }
      return {
        'resultType': 'complete',
        'content': [
          {'type': 'text', 'text': 'done'},
        ],
      };
    });

    final result = await harness.connection.callTool(
      CallToolRequest(
        name: 'task',
        arguments: {'keep': 1},
        meta: MetaWithProgressToken(progressToken: ProgressToken('progress')),
      ),
    );

    expect((result.content.single as TextContent).text, 'done');
    expect(harness.requests, hasLength(2));
    expect(
      client.handled,
      unorderedEquals([
        'elicitation/create',
        'sampling/createMessage',
        'roots/list',
      ]),
    );
    final first = _params(harness.requests.first);
    final retry = _params(harness.requests.last);
    expect(first, {
      'name': 'task',
      'arguments': {'keep': 1},
      '_meta': {'progressToken': 'progress'},
    });
    expect(retry['name'], 'task');
    expect(retry['arguments'], {'keep': 1});
    expect(retry['_meta'], {'progressToken': 'progress'});
    expect(retry['requestState'], 'opaque-state');
    final responses = retry['inputResponses'] as Map;
    expect(responses.keys, unorderedEquals(['form', 'sample', 'roots']));
    expect((responses['form'] as Map)['action'], 'accept');
    expect((responses['sample'] as Map)['model'], 'test-model');
    expect((responses['roots'] as Map)['roots'], [
      {'uri': 'file:///workspace', 'name': 'workspace'},
    ]);
    expect(harness.requests.first['id'], isNot(harness.requests.last['id']));
  });

  final requestCases = <
    ({
      String method,
      Future<void> Function(ServerConnection) invoke,
      Map<String, Object?> terminal,
    })
  >[
    (
      method: 'tools/call',
      invoke: (connection) async {
        final result = await connection.callTool(CallToolRequest(name: 'task'));
        expect((result.content.single as TextContent).text, 'done');
      },
      terminal: {
        'resultType': 'complete',
        'content': [
          {'type': 'text', 'text': 'done'},
        ],
      },
    ),
    (
      method: 'prompts/get',
      invoke: (connection) async {
        final result = await connection.getPrompt(GetPromptRequest(name: 'p'));
        expect(result.messages, hasLength(1));
      },
      terminal: {
        'resultType': 'complete',
        'messages': [
          {
            'role': 'assistant',
            'content': {'type': 'text', 'text': 'done'},
          },
        ],
      },
    ),
    (
      method: 'resources/read',
      invoke: (connection) async {
        final result = await connection.readResource(
          ReadResourceRequest(uri: 'file:///resource'),
        );
        expect(result.contents, hasLength(1));
      },
      terminal: {
        'resultType': 'complete',
        'contents': [
          {'uri': 'file:///resource', 'text': 'done'},
        ],
      },
    ),
  ];
  for (final requestCase in requestCases) {
    test('retries ${requestCase.method} with request state', () async {
      final harness = _WireHarness(_InputClient(), (request, requestNumber) {
        if (requestNumber == 1) {
          return {'resultType': 'input_required', 'requestState': 'state-only'};
        }
        return requestCase.terminal;
      });

      await requestCase.invoke(harness.connection);

      expect(harness.requests, hasLength(2));
      expect(harness.requests.map((request) => request['method']), [
        requestCase.method,
        requestCase.method,
      ]);
      expect(_params(harness.requests.first), isNot(contains('requestState')));
      expect(_params(harness.requests.last)['requestState'], 'state-only');
      expect(_params(harness.requests.last), isNot(contains('inputResponses')));
      expect(harness.requests.first['id'], isNot(harness.requests.last['id']));
    });
  }

  test('uses only the latest input responses on a later round', () async {
    final client =
        _InputClient()
          ..addRoot(Root(uri: 'file:///workspace', name: 'workspace'));
    final harness = _WireHarness(client, (request, requestNumber) {
      return switch (requestNumber) {
        1 => {
          'resultType': 'input_required',
          'inputRequests': {
            'form': {
              'method': 'elicitation/create',
              'params': {
                'mode': 'form',
                'message': 'Enter a value',
                'requestedSchema': {
                  'type': 'object',
                  'properties': <String, Object?>{},
                },
              },
            },
          },
          'requestState': 'first-state',
        },
        2 => {
          'resultType': 'input_required',
          'inputRequests': {
            'roots': {'method': 'roots/list', 'params': <String, Object?>{}},
          },
        },
        _ => {
          'resultType': 'complete',
          'content': [
            {'type': 'text', 'text': 'done'},
          ],
        },
      };
    });

    await harness.connection.callTool(
      CallToolRequest(
        name: 'task',
        inputResponses: {
          'old': ElicitResult(action: ElicitationAction.decline),
        },
        requestState: 'old-state',
      ),
    );

    expect(harness.requests, hasLength(3));
    final initial = _params(harness.requests.first);
    final firstRetry = _params(harness.requests[1]);
    final secondRetry = _params(harness.requests[2]);
    expect((initial['inputResponses'] as Map).keys, ['old']);
    expect(initial['requestState'], 'old-state');
    expect((firstRetry['inputResponses'] as Map).keys, ['form']);
    expect(firstRetry['requestState'], 'first-state');
    expect((secondRetry['inputResponses'] as Map).keys, ['roots']);
    expect(secondRetry, isNot(contains('requestState')));
  });

  test('stops when an input request needs an undeclared capability', () async {
    final client = _ElicitationClient();
    final harness = _WireHarness(
      client,
      (request, requestNumber) => {
        'resultType': 'input_required',
        'inputRequests': {
          'form': {
            'method': 'elicitation/create',
            'params': {
              'mode': 'form',
              'message': 'Enter a value',
              'requestedSchema': {
                'type': 'object',
                'properties': <String, Object?>{},
              },
            },
          },
          'sample': {
            'method': 'sampling/createMessage',
            'params': {'messages': <Object?>[], 'maxTokens': 1},
          },
        },
      },
    );

    await expectLater(
      harness.connection.callTool(CallToolRequest(name: 'task')),
      throwsA(
        isA<RpcException>()
            .having((error) => error.code, 'code', -32021)
            .having(
              (error) => (error.data as Map)['requiredCapabilities'],
              'required capabilities',
              {'sampling': <String, Object?>{}},
            ),
      ),
    );
    expect(harness.requests, hasLength(1));
    expect(client.callCount, 0);
  });

  test('stops after ten input-required retry rounds', () async {
    final harness = _WireHarness(
      MCPClient(Implementation(name: 'test client', version: '0.1.0')),
      (request, requestNumber) => {
        'resultType': 'input_required',
        'requestState': 'still-waiting',
      },
    );

    await expectLater(
      harness.connection.callTool(CallToolRequest(name: 'task')),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          allOf(contains('input_required'), contains('10')),
        ),
      ),
    );
    expect(harness.requests, hasLength(11));
    expect(
      harness.requests.map((request) => request['id']).toSet(),
      hasLength(11),
    );
  });
}

Map<String, Object?> _params(Map<String, Object?> request) =>
    (request['params'] as Map).cast<String, Object?>();

typedef _Responder =
    Map<String, Object?> Function(
      Map<String, Object?> request,
      int requestNumber,
    );

final class _WireHarness {
  final MCPClient client;
  final _Responder _respond;
  final _incoming = StreamController<Map<String, Object?>>();
  final _outgoing = StreamController<Map<String, Object?>>();
  final requests = <Map<String, Object?>>[];
  late final ServerConnection connection;
  late final StreamSubscription<Map<String, Object?>> _subscription;

  _WireHarness(this.client, this._respond) {
    connection = client.connectServer(
      StreamChannel.withGuarantees(_incoming.stream, _outgoing.sink),
    );
    connection.serverInfo = Implementation(name: 'wire server', version: '1');
    _subscription = _outgoing.stream.listen((request) {
      requests.add(request);
      _incoming.add({
        'jsonrpc': '2.0',
        'id': request['id'],
        'result': _respond(request, requests.length),
      });
    });
    addTearDown(_close);
  }

  Future<void> _close() async {
    await client.shutdown();
    await _subscription.cancel();
    await _incoming.close();
  }
}

final class _InputClient extends MCPClient
    with RootsSupport, SamplingSupport, ElicitationFormSupport {
  final handled = <String>[];

  _InputClient() : super(Implementation(name: 'test client', version: '0.1.0'));

  @override
  FutureOr<ElicitResult> handleElicitation(
    ElicitRequest request,
    ServerConnection connection,
  ) {
    handled.add('elicitation/create');
    return ElicitResult(
      action: ElicitationAction.accept,
      content: {'answer': 'accepted'},
    );
  }

  @override
  FutureOr<CreateMessageResult> handleCreateMessage(
    CreateMessageRequest request,
    Implementation serverInfo,
  ) {
    handled.add('sampling/createMessage');
    return CreateMessageResult(
      role: Role.assistant,
      content: Content.text(text: 'sampled'),
      model: 'test-model',
    );
  }

  @override
  FutureOr<ListRootsResult> handleListRoots([ListRootsRequest? request]) {
    handled.add('roots/list');
    return super.handleListRoots(request);
  }
}

final class _ElicitationClient extends MCPClient with ElicitationFormSupport {
  int callCount = 0;

  _ElicitationClient()
    : super(Implementation(name: 'test client', version: '0.1.0'));

  @override
  FutureOr<ElicitResult> handleElicitation(
    ElicitRequest request,
    ServerConnection connection,
  ) {
    callCount++;
    return ElicitResult(action: ElicitationAction.accept);
  }
}
