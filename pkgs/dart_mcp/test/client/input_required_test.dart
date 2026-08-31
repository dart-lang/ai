// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/client.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

void main() {
  test('does not interpret input-required results before 2026-07-28', () async {
    final client = MCPClient(
      Implementation(name: 'test client', version: '0.1.0'),
    );
    final harness = _WireHarness(client, (request, requestNumber) {
      return switch (request['method']) {
        InitializeRequest.methodName => {
          'protocolVersion': '2025-11-25',
          'capabilities': <String, Object?>{},
          'serverInfo': {'name': 'wire server', 'version': '1'},
        },
        CallToolRequest.methodName => {
          'resultType': 'input_required',
          'content': [
            {'type': 'text', 'text': 'legacy result'},
          ],
        },
        _ => throw StateError('Unexpected method ${request['method']}'),
      };
    }, protocolVersion: null);

    await harness.connection.initialize(
      InitializeRequest(
        protocolVersion: ProtocolVersion.v2025_11_25,
        capabilities: client.capabilities,
        clientInfo: client.implementation,
      ),
    );
    final result = await harness.connection.callTool(
      CallToolRequest(name: 'task'),
    );

    expect(harness.connection.protocolVersion, ProtocolVersion.v2025_11_25);
    expect((result.content.single as TextContent).text, 'legacy result');
    expect(harness.requests.map((request) => request['method']), [
      InitializeRequest.methodName,
      CallToolRequest.methodName,
    ]);
  });

  test('treats an unsettled version like one before 2026-07-28', () async {
    final client =
        _InputClient()
          ..addRoot(Root(uri: 'file:///workspace', name: 'workspace'));
    final harness = _WireHarness(
      client,
      (request, requestNumber) => {
        'resultType': 'input_required',
        'content': [
          {'type': 'text', 'text': 'unsettled result'},
        ],
        'inputRequests': {
          'roots': {'method': 'roots/list', 'params': <String, Object?>{}},
        },
      },
      protocolVersion: null,
    );

    final result = await harness.connection.callTool(
      CallToolRequest(name: 'task'),
    );

    expect(harness.connection.protocolVersion, isNull);
    expect((result.content.single as TextContent).text, 'unsettled result');
    expect(client.handled, isEmpty);
    expect(harness.requests, hasLength(1));
  });

  test('retries on a connection whose transport settled the version', () async {
    final client =
        _InputClient()
          ..addRoot(Root(uri: 'file:///workspace', name: 'workspace'));
    final harness = _WireHarness(client, (request, requestNumber) {
      if (requestNumber == 1) {
        return {
          'resultType': 'input_required',
          'inputRequests': {
            'roots': {'method': 'roots/list', 'params': <String, Object?>{}},
          },
        };
      }
      return {
        'resultType': 'complete',
        'content': [
          {'type': 'text', 'text': 'done'},
        ],
      };
    }, withServerInfo: false);

    final result = await harness.connection.callTool(
      CallToolRequest(name: 'task'),
    );

    expect(harness.connection.serverInfo, isNull);
    expect((result.content.single as TextContent).text, 'done');
    expect(client.handled, ['roots/list']);
    expect(harness.requests, hasLength(2));
    expect((_params(harness.requests.last)['inputResponses'] as Map).keys, [
      'roots',
    ]);
  });

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

  test('retries after accepting a URL elicitation', () async {
    final client = _UrlInputClient();
    final harness = _WireHarness(client, (request, requestNumber) {
      if (requestNumber == 1) {
        return {
          'resultType': 'input_required',
          'inputRequests': {
            'url': {
              'method': 'elicitation/create',
              'params': {
                'mode': 'url',
                'message': 'Open the URL',
                'url': 'https://example.com',
              },
            },
          },
          'requestState': 'url-state',
        };
      }
      return {
        'resultType': 'complete',
        'content': [
          {'type': 'text', 'text': 'done'},
        ],
      };
    });

    await harness.connection.callTool(CallToolRequest(name: 'task'));

    expect(client.callCount, 1);
    expect(harness.requests, hasLength(2));
    final retry = _params(harness.requests.last);
    expect(retry['requestState'], 'url-state');
    expect(
      ((retry['inputResponses'] as Map)['url'] as Map)['action'],
      'accept',
    );
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

  test(
    'drops earlier input responses on a round that answers nothing',
    () async {
      final harness = _WireHarness(
        MCPClient(Implementation(name: 'test client', version: '0.1.0')),
        (request, requestNumber) =>
            requestNumber == 1
                ? {'resultType': 'input_required', 'requestState': 'state-only'}
                : {
                  'resultType': 'complete',
                  'content': [
                    {'type': 'text', 'text': 'done'},
                  ],
                },
      );

      await harness.connection.callTool(
        CallToolRequest(
          name: 'task',
          inputResponses: {
            'old': ElicitResult(action: ElicitationAction.decline),
          },
        ),
      );

      expect(harness.requests, hasLength(2));
      expect((_params(harness.requests.first)['inputResponses'] as Map).keys, [
        'old',
      ]);
      final retry = _params(harness.requests.last);
      expect(retry, isNot(contains('inputResponses')));
      expect(retry['requestState'], 'state-only');
    },
  );

  for (final boundaryCase in [
    (
      name: 'an empty request state',
      result: <String, Object?>{
        'resultType': 'input_required',
        'requestState': '',
      },
      expectedState: '',
    ),
    (
      name: 'an empty input request map',
      result: <String, Object?>{
        'resultType': 'input_required',
        'inputRequests': <String, Object?>{},
      },
      expectedState: null,
    ),
  ]) {
    test('retries with ${boundaryCase.name}', () async {
      final harness = _WireHarness(
        MCPClient(Implementation(name: 'test client', version: '0.1.0')),
        (request, requestNumber) =>
            requestNumber == 1
                ? boundaryCase.result
                : {
                  'resultType': 'complete',
                  'content': [
                    {'type': 'text', 'text': 'done'},
                  ],
                },
      );

      await harness.connection.callTool(CallToolRequest(name: 'task'));

      final retry = _params(harness.requests.last);
      expect(retry['requestState'], boundaryCase.expectedState);
      expect(retry, isNot(contains('inputResponses')));
    });
  }

  for (final method in [
    ElicitRequest.methodName,
    CreateMessageRequest.methodName,
    ListRootsRequest.methodName,
  ]) {
    test('rejects non-object params for $method', () async {
      final harness = _WireHarness(
        _InputClient(),
        (request, requestNumber) => {
          'resultType': 'input_required',
          'inputRequests': {
            'invalid': {'method': method, 'params': 'not an object'},
          },
        },
      );

      await expectLater(
        harness.connection.callTool(CallToolRequest(name: 'task')),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            allOf(contains(method), contains('expected an object')),
          ),
        ),
      );
      expect(harness.requests, hasLength(1));
    });
  }

  for (final method in [
    ElicitRequest.methodName,
    CreateMessageRequest.methodName,
  ]) {
    test('rejects absent params for $method', () async {
      final harness = _WireHarness(
        _InputClient(),
        (request, requestNumber) => {
          'resultType': 'input_required',
          'inputRequests': {
            'absent': {'method': method},
          },
        },
      );

      await expectLater(
        harness.connection.callTool(CallToolRequest(name: 'task')),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            allOf(contains(method), contains('expected an object')),
          ),
        ),
      );
      expect(harness.requests, hasLength(1));
    });
  }

  test('answers a roots/list request that carries no params', () async {
    final client =
        _InputClient()
          ..addRoot(Root(uri: 'file:///workspace', name: 'workspace'));
    final harness = _WireHarness(
      client,
      (request, requestNumber) =>
          requestNumber == 1
              ? {
                'resultType': 'input_required',
                'inputRequests': {
                  'roots': {'method': 'roots/list'},
                },
              }
              : {
                'resultType': 'complete',
                'content': [
                  {'type': 'text', 'text': 'done'},
                ],
              },
    );

    await harness.connection.callTool(CallToolRequest(name: 'task'));

    expect(client.handled, ['roots/list']);
    expect(harness.requests, hasLength(2));
    expect((_params(harness.requests.last)['inputResponses'] as Map).keys, [
      'roots',
    ]);
  });

  test('rejects an input request whose elicitation mode is unknown', () async {
    final client = _InputClient();
    final harness = _WireHarness(
      client,
      (request, requestNumber) => {
        'resultType': 'input_required',
        'inputRequests': {
          'form': {
            'method': 'elicitation/create',
            'params': {'mode': 'voice', 'message': 'Enter a value'},
          },
        },
      },
    );

    await expectLater(
      harness.connection.callTool(CallToolRequest(name: 'task')),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          allOf(contains('voice'), contains('form')),
        ),
      ),
    );
    expect(harness.requests, hasLength(1));
    expect(client.handled, isEmpty);
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
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('sampling'),
        ),
      ),
    );
    expect(harness.requests, hasLength(1));
    expect(client.callCount, 0);
  });

  test('stops when a sampling input request has no serverInfo', () async {
    final client = _InputClient();
    final harness = _WireHarness(
      client,
      (request, requestNumber) => {
        'resultType': 'input_required',
        'inputRequests': {
          'sample': {
            'method': 'sampling/createMessage',
            'params': {'messages': <Object?>[], 'maxTokens': 1},
          },
        },
      },
      withServerInfo: false,
    );

    await expectLater(
      harness.connection.callTool(CallToolRequest(name: 'task')),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('serverInfo'),
        ),
      ),
    );
    expect(harness.requests, hasLength(1));
    expect(client.handled, isEmpty);
  });

  test('names the missing serverInfo on a direct sampling request', () async {
    final client = _InputClient();
    final harness = _WireHarness(
      client,
      (request, requestNumber) => throw StateError('no client requests here'),
      withServerInfo: false,
    );

    harness.send({
      'jsonrpc': '2.0',
      'id': 'sample',
      'method': CreateMessageRequest.methodName,
      'params': {'messages': <Object?>[], 'maxTokens': 1},
    });
    await pumpEventQueue();

    expect(
      (harness.responses.single['error'] as Map)['message'],
      contains('`serverInfo`'),
    );
    expect(client.handled, isEmpty);
  });

  test('rejects an input-required result without requests or state', () async {
    final harness = _WireHarness(
      MCPClient(Implementation(name: 'test client', version: '0.1.0')),
      (request, requestNumber) => {'resultType': 'input_required'},
    );

    await expectLater(
      harness.connection.callTool(CallToolRequest(name: 'task')),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          allOf(contains('inputRequests'), contains('requestState')),
        ),
      ),
    );
    expect(harness.requests, hasLength(1));
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
        isA<ArgumentError>().having(
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

  test('stops after the rounds the caller set', () async {
    final harness = _WireHarness(
      MCPClient(Implementation(name: 'test client', version: '0.1.0')),
      (request, requestNumber) => {
        'resultType': 'input_required',
        'requestState': 'still-waiting',
      },
    );
    harness.connection.maxInputRequiredRounds = 2;

    await expectLater(
      harness.connection.callTool(CallToolRequest(name: 'task')),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          allOf(contains('input_required'), contains('2')),
        ),
      ),
    );
    expect(harness.requests, hasLength(3));
  });

  test('stops without retrying on a negative round cap', () async {
    final harness = _WireHarness(
      MCPClient(Implementation(name: 'test client', version: '0.1.0')),
      (request, requestNumber) =>
          requestNumber == 1
              ? {
                'resultType': 'input_required',
                'requestState': 'still-waiting',
              }
              : {
                'resultType': 'complete',
                'content': [
                  {'type': 'text', 'text': 'done'},
                ],
              },
    );
    harness.connection.maxInputRequiredRounds = -1;

    await expectLater(
      harness.connection.callTool(CallToolRequest(name: 'task')),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          allOf(contains('input_required'), contains('0 retries')),
        ),
      ),
    );
    expect(harness.requests, hasLength(1));
  });

  test('answers past the default cap when the caller clears it', () async {
    final harness = _WireHarness(
      MCPClient(Implementation(name: 'test client', version: '0.1.0')),
      (request, requestNumber) =>
          requestNumber <= 12
              ? {
                'resultType': 'input_required',
                'requestState': 'still-waiting',
              }
              : {
                'resultType': 'complete',
                'content': [
                  {'type': 'text', 'text': 'done'},
                ],
              },
    );
    harness.connection.maxInputRequiredRounds = null;

    final result = await harness.connection.callTool(
      CallToolRequest(name: 'task'),
    );

    expect((result.content.single as TextContent).text, 'done');
    expect(harness.requests, hasLength(13));
  });

  test('reports progress from every round under the original token', () async {
    final harness = _WireHarness(
      MCPClient(Implementation(name: 'test client', version: '0.1.0')),
      (request, requestNumber) =>
          requestNumber == 1
              ? {'resultType': 'input_required', 'requestState': 'state'}
              : {
                'resultType': 'complete',
                'content': [
                  {'type': 'text', 'text': 'done'},
                ],
              },
      sendProgress: true,
    );
    final request = CallToolRequest(
      name: 'task',
      meta: MetaWithProgressToken(progressToken: ProgressToken('token')),
    );
    final progress = <num>[];
    var streamClosed = false;
    harness.connection
        .onProgress(request)
        .listen(
          (notification) => progress.add(notification.progress),
          onDone: () => streamClosed = true,
        );

    await harness.connection.callTool(request);
    await pumpEventQueue();

    expect(harness.requests, hasLength(2));
    expect(harness.progressSent, 2);
    expect(progress, [1, 2]);
    expect(streamClosed, isTrue);
  });

  test('closes the progress stream once the retries stop', () async {
    final harness = _WireHarness(
      MCPClient(Implementation(name: 'test client', version: '0.1.0')),
      (request, requestNumber) => {
        'resultType': 'input_required',
        'requestState': 'still-waiting',
      },
      sendProgress: true,
    );
    final request = CallToolRequest(
      name: 'task',
      meta: MetaWithProgressToken(progressToken: ProgressToken('token')),
    );
    final progress = <num>[];
    var streamClosed = false;
    harness.connection
        .onProgress(request)
        .listen(
          (notification) => progress.add(notification.progress),
          onDone: () => streamClosed = true,
        );

    await expectLater(
      harness.connection.callTool(request),
      throwsA(isA<ArgumentError>()),
    );
    await pumpEventQueue();

    expect(harness.requests, hasLength(11));
    expect(
      harness.requests.map((request) => _params(request)['_meta']),
      everyElement({'progressToken': 'token'}),
    );
    expect(progress, hasLength(11));
    expect(streamClosed, isTrue);
  });

  test(
    'releases the progress token on a connection before 2026-07-28',
    () async {
      final harness = _WireHarness(
        MCPClient(Implementation(name: 'test client', version: '0.1.0')),
        (request, requestNumber) => {
          'resultType': 'input_required',
          'requestState': 'state',
        },
        protocolVersion: ProtocolVersion.v2025_11_25,
      );
      final request = CallToolRequest(
        name: 'task',
        meta: MetaWithProgressToken(progressToken: ProgressToken('token')),
      );
      var streamClosed = false;
      harness.connection
          .onProgress(request)
          .listen((notification) {}, onDone: () => streamClosed = true);

      await harness.connection.callTool(request);
      await pumpEventQueue();

      expect(harness.requests, hasLength(1));
      expect(streamClosed, isTrue);
    },
  );
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

  /// Whether to answer a request carrying a progress token with one progress
  /// notification before its result.
  final bool sendProgress;

  final _incoming = StreamController<Map<String, Object?>>();
  final _outgoing = StreamController<Map<String, Object?>>();
  final requests = <Map<String, Object?>>[];

  /// What this client answered the requests [send] made, in order.
  final responses = <Map<String, Object?>>[];

  /// How many progress notifications [sendProgress] has sent so far.
  int progressSent = 0;

  late final ServerConnection connection;
  late final StreamSubscription<Map<String, Object?>> _subscription;

  _WireHarness(
    this.client,
    this._respond, {
    ProtocolVersion? protocolVersion = ProtocolVersion.v2026_07_28,
    this.sendProgress = false,
    bool withServerInfo = true,
  }) {
    connection = client.connectServer(
      StreamChannel.withGuarantees(_incoming.stream, _outgoing.sink),
    );
    connection.protocolVersion = protocolVersion;
    if (protocolVersion != null && withServerInfo) {
      connection.serverInfo = Implementation(name: 'wire server', version: '1');
    }
    _subscription = _outgoing.stream.listen((request) {
      if (!request.containsKey('method')) {
        responses.add(request);
        return;
      }
      requests.add(request);
      final token = (_params(request)['_meta'] as Map?)?['progressToken'];
      if (sendProgress && token != null) {
        _incoming.add({
          'jsonrpc': '2.0',
          'method': ProgressNotification.methodName,
          'params': {'progressToken': token, 'progress': ++progressSent},
        });
      }
      _incoming.add({
        'jsonrpc': '2.0',
        'id': request['id'],
        'result': _respond(request, requests.length),
      });
    });
    addTearDown(_close);
  }

  /// Sends [request] to the client the way a server would.
  void send(Map<String, Object?> request) => _incoming.add(request);

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

final class _UrlInputClient extends MCPClient with ElicitationUrlSupport {
  int callCount = 0;

  _UrlInputClient()
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
