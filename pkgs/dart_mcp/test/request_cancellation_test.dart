// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/src/shared.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

void main() {
  group('a client', () {
    test('cancels a call with a notification and stops waiting', () async {
      final wire = _ClientWire();
      final request = CallToolRequest(name: 'slow');
      final result = wire.connection.callTool(request);
      await pumpEventQueue();

      final cancelling = wire.connection.cancelRequest(
        request,
        reason: 'user said so',
      );

      await expectLater(
        result,
        throwsA(
          isA<RequestCancelledException>().having(
            (e) => e.reason,
            'reason',
            'user said so',
          ),
        ),
      );
      await cancelling;
      expect(wire.cancellations, [
        {'requestId': wire.requestIds.single, 'reason': 'user said so'},
      ]);
    });

    test('ignores a response that arrives after the cancellation', () async {
      final wire = _ClientWire();
      final request = CallToolRequest(name: 'slow');
      final result = wire.connection.callTool(request);
      await pumpEventQueue();
      final cancelling = wire.connection.cancelRequest(request);
      await expectLater(result, throwsA(isA<RequestCancelledException>()));
      await cancelling;

      wire.respond(wire.requestIds.single, {'content': <Object?>[]});
      await pumpEventQueue();

      expect(wire.connection.isActive, isTrue);
      final next = wire.connection.callTool(CallToolRequest(name: 'next'));
      await pumpEventQueue();
      wire.respond(wire.requestIds.last, {'content': <Object?>[]});
      expect((await next).content, isEmpty);
    });

    test('fails the call when the response raced the cancellation', () async {
      final wire = _ClientWire();
      final request = CallToolRequest(name: 'slow');
      final result = wire.connection.callTool(request);
      await pumpEventQueue();

      wire.respond(wire.requestIds.single, {'content': <Object?>[]});
      final cancelling = wire.connection.cancelRequest(request);

      await expectLater(result, throwsA(isA<RequestCancelledException>()));
      await cancelling;
    });

    test('does nothing for a request never sent or already done', () async {
      final wire = _ClientWire();
      await wire.connection.cancelRequest(CallToolRequest(name: 'unsent'));

      final request = CallToolRequest(name: 'done');
      final result = wire.connection.callTool(request);
      await pumpEventQueue();
      wire.respond(wire.requestIds.single, {'content': <Object?>[]});
      await result;
      await wire.connection.cancelRequest(request);

      expect(wire.cancellations, isEmpty);
      expect((await result).content, isEmpty);
    });

    test('can send a request again after cancelling it', () async {
      final wire = _ClientWire();
      final request = CallToolRequest(name: 'again');
      final first = wire.connection.callTool(request);
      await pumpEventQueue();
      final cancelling = wire.connection.cancelRequest(request);
      await expectLater(first, throwsA(isA<RequestCancelledException>()));
      await cancelling;

      final second = wire.connection.callTool(request);
      await pumpEventQueue();
      wire.respond(wire.requestIds.last, {'content': <Object?>[]});

      expect((await second).content, isEmpty);
    });

    test('cancels every call in flight with the same request', () async {
      final wire = _ClientWire();
      final request = CallToolRequest(name: 'twice');
      final calls = [
        for (var i = 0; i < 2; i++)
          expectLater(
            wire.connection.callTool(request),
            throwsA(isA<RequestCancelledException>()),
          ),
      ];
      await pumpEventQueue();

      await wire.connection.cancelRequest(request);

      await Future.wait(calls);
      expect(
        wire.cancellations.map((params) => params['requestId']),
        unorderedEquals(wire.requestIds),
      );
    });

    test('cancels a call sent with a constant request', () async {
      final wire = _ClientWire(protocolVersion: ProtocolVersion.v2026_07_28);
      final request = ListToolsRequest.fromMap(const {});
      final result = wire.connection.listTools(request);
      await pumpEventQueue();

      final cancelling = wire.connection.cancelRequest(request);

      await expectLater(result, throwsA(isA<RequestCancelledException>()));
      await cancelling;
      expect(wire.requestIds, hasLength(1));
      final next = wire.connection.listTools(request);
      await pumpEventQueue();
      wire.respond(wire.requestIds.last, {
        'tools': <Object?>[],
        'resultType': 'complete',
        'ttlMs': 0,
        'cacheScope': 'private',
      });
      expect((await next).tools, isEmpty);
    });

    test('refuses to cancel initialize', () async {
      final wire = _ClientWire(protocolVersion: null);
      final request = InitializeRequest(
        protocolVersion: ProtocolVersion.v2025_11_25,
        capabilities: ClientCapabilities(),
        clientInfo: Implementation(name: 'client', version: '1'),
      );
      // ignore: deprecated_member_use_from_same_package
      final result = wire.connection.initialize(request);
      await pumpEventQueue();

      expect(() => wire.connection.cancelRequest(request), throwsArgumentError);
      wire.respond(wire.requestIds.single, {
        'protocolVersion': '2025-11-25',
        'capabilities': <String, Object?>{},
        'serverInfo': {'name': 'server', 'version': '1'},
      });
      expect((await result).protocolVersion, ProtocolVersion.v2025_11_25);
      expect(wire.cancellations, isEmpty);
    });

    test('cancels a list call waiting on an identical one', () async {
      final wire = _ClientWire(protocolVersion: ProtocolVersion.v2026_07_28);
      final first = wire.connection.listTools(ListToolsRequest());
      await pumpEventQueue();
      final request = ListToolsRequest();
      final second = wire.connection.listTools(request);
      await pumpEventQueue();

      final cancelling = wire.connection.cancelRequest(request);

      await expectLater(second, throwsA(isA<RequestCancelledException>()));
      await cancelling;
      wire.respond(wire.requestIds.single, {
        'tools': <Object?>[],
        'resultType': 'complete',
        'ttlMs': 0,
        'cacheScope': 'private',
      });
      await first;
      await pumpEventQueue();
      expect(wire.requestIds, hasLength(1));
    });

    test('cancels through a channel that closes the request', () async {
      final cancelled = <RequestId>[];
      final wire = _ClientWire(
        protocolVersion: ProtocolVersion.v2026_07_28,
        wrap: (channel) => _CancellingChannel(channel, cancelled.add),
      );
      final request = CallToolRequest(name: 'slow');
      final result = wire.connection.callTool(request);
      await pumpEventQueue();

      final cancelling = wire.connection.cancelRequest(request);

      await expectLater(result, throwsA(isA<RequestCancelledException>()));
      await cancelling;
      expect(cancelled, [wire.requestIds.single]);
      expect(wire.cancellations, isEmpty);
    });

    test('stops an input_required call between rounds', () async {
      final client = _GatedElicitationClient();
      final wire = _ClientWire(
        client: client,
        protocolVersion: ProtocolVersion.v2026_07_28,
      );
      final request = CallToolRequest(name: 'asks');
      final result = wire.connection.callTool(request);
      await pumpEventQueue();
      wire.respond(wire.requestIds.single, _inputRequired);
      await client.asked.future;

      final cancelling = wire.connection.cancelRequest(request);
      client.answer.complete();

      await expectLater(result, throwsA(isA<RequestCancelledException>()));
      await cancelling;
      expect(wire.requestIds, hasLength(1));
      expect(wire.cancellations, isEmpty);
    });

    test('cancels the retry an input_required call sent', () async {
      final client = _GatedElicitationClient()..answer.complete();
      final wire = _ClientWire(
        client: client,
        protocolVersion: ProtocolVersion.v2026_07_28,
      );
      final request = CallToolRequest(name: 'asks');
      final result = wire.connection.callTool(request);
      await pumpEventQueue();
      wire.respond(wire.requestIds.single, _inputRequired);
      await pumpEventQueue();
      expect(wire.requestIds, hasLength(2));

      final cancelling = wire.connection.cancelRequest(request);

      await expectLater(result, throwsA(isA<RequestCancelledException>()));
      await cancelling;
      expect(wire.cancellations, [
        {'requestId': wire.requestIds.last},
      ]);
    });
  });

  group('a server', () {
    test('cancels its request with a notification before 2026-07-28', () async {
      final wire = await _ServerWire.start(ProtocolVersion.v2025_11_25);
      final request = PingRequest();
      final result = wire.server.sendRequest<EmptyResult>(
        PingRequest.methodName,
        request,
      );

      final cancelling = wire.server.cancelRequest(request, reason: 'too slow');

      await expectLater(result, throwsA(isA<RequestCancelledException>()));
      await cancelling;
      await pumpEventQueue();
      expect(wire.cancellations, [
        {'requestId': wire.requestIds.single, 'reason': 'too slow'},
      ]);
    });

    test(
      'fails the call when an error response raced the cancellation',
      () async {
        final wire = await _ServerWire.start(ProtocolVersion.v2025_11_25);
        final request = PingRequest();
        final result = expectLater(
          wire.server.sendRequest<EmptyResult>(PingRequest.methodName, request),
          throwsA(isA<RequestCancelledException>()),
        );
        await pumpEventQueue();

        wire.toPeer.add({
          'jsonrpc': '2.0',
          'id': wire.requestIds.single,
          'error': {'code': -32603, 'message': 'failed'},
        });
        await wire.server.cancelRequest(request);

        await result;
      },
    );

    test('notifies from a handler whose own request was cancelled', () async {
      final wire = await _ServerWire.start(ProtocolVersion.v2025_11_25);
      final ping = PingRequest();
      final cancelled = Completer<void>();
      wire.server.registerRequestHandler('test/slow', (Request? _) async {
        final pong = expectLater(
          wire.server.sendRequest<EmptyResult>(PingRequest.methodName, ping),
          throwsA(isA<RequestCancelledException>()),
        );
        await cancelled.future;
        await wire.server.cancelRequest(ping);
        await pong;
        return EmptyResult();
      });
      wire.toPeer.add({'jsonrpc': '2.0', 'id': 'slow', 'method': 'test/slow'});
      await pumpEventQueue();
      wire.toPeer.add({
        'jsonrpc': '2.0',
        'method': CancelledNotification.methodName,
        'params': {'requestId': 'slow'},
      });
      await pumpEventQueue();

      cancelled.complete();
      await pumpEventQueue();

      expect(wire.cancellations, [
        {'requestId': wire.requestIds.single},
      ]);
    });

    test('sends no notification on 2026-07-28', () async {
      final wire = await _ServerWire.start(ProtocolVersion.v2026_07_28);
      final request = PingRequest();
      final result = wire.server.sendRequest<EmptyResult>(
        PingRequest.methodName,
        request,
      );

      final cancelling = wire.server.cancelRequest(request);

      await expectLater(result, throwsA(isA<RequestCancelledException>()));
      await cancelling;
      expect(wire.requestIds, hasLength(1));
      expect(wire.cancellations, isEmpty);
    });
  });
}

final _inputRequired = {
  'resultType': 'input_required',
  'inputRequests': {
    'answer': {
      'method': ElicitRequest.methodName,
      'params': ElicitRequest.form(
        message: 'Which one?',
        requestedSchema: ObjectSchema(),
      ),
    },
  },
};

mixin _Frames {
  final toPeer = StreamController<Map<String, Object?>>();
  final fromPeer = StreamController<Map<String, Object?>>();
  final frames = <Map<String, Object?>>[];

  StreamChannel<Map<String, Object?>> get channel {
    fromPeer.stream.listen(frames.add);
    return StreamChannel.withCloseGuarantee(toPeer.stream, fromPeer.sink);
  }

  List<Object?> get requestIds => [
    for (final frame in frames)
      if (frame.containsKey('method') && frame.containsKey('id')) frame['id'],
  ];

  List<Map<String, Object?>> get cancellations => [
    for (final frame in frames)
      if (frame['method'] == CancelledNotification.methodName)
        frame['params'] as Map<String, Object?>,
  ];

  void respond(Object? id, Map<String, Object?> result) =>
      toPeer.add({'jsonrpc': '2.0', 'id': id, 'result': result});
}

final class _ClientWire with _Frames {
  late final ServerConnection connection;

  _ClientWire({
    MCPClient? client,
    ProtocolVersion? protocolVersion = ProtocolVersion.v2025_11_25,
    StreamChannel<Map<String, Object?>> Function(
      StreamChannel<Map<String, Object?>>,
    )?
    wrap,
  }) {
    client ??= MCPClient(Implementation(name: 'client', version: '1'));
    final raw = channel;
    connection = client.connectServer(wrap?.call(raw) ?? raw);
    connection
      ..protocolVersion = protocolVersion
      ..inputRequiredRetryDelay = null
      ..serverInfo = Implementation(name: 'server', version: '1');
    addTearDown(client.shutdown);
  }
}

final class _ServerWire with _Frames {
  late final _Server server;

  static Future<_ServerWire> start(ProtocolVersion protocolVersion) async {
    final wire = _ServerWire();
    wire.server = _Server(wire.channel);
    addTearDown(wire.server.shutdown);
    await wire.server.initialize(
      MCPServerInitialization(
        protocolVersion: protocolVersion,
        clientCapabilities: ClientCapabilities(),
      ),
    );
    return wire;
  }
}

final class _Server extends MCPServer {
  _Server(super.channel)
    : super.fromStreamChannel(
        implementation: Implementation(name: 'server', version: '1'),
      );
}

final class _GatedElicitationClient extends MCPClient
    with ElicitationFormSupport {
  final asked = Completer<void>();
  final answer = Completer<void>();

  _GatedElicitationClient()
    : super(Implementation(name: 'client', version: '1'));

  @override
  Future<ElicitResult> handleElicitation(
    ElicitRequest request,
    ServerConnection connection,
  ) async {
    asked.complete();
    await answer.future;
    return ElicitResult(action: ElicitationAction.decline);
  }
}

final class _CancellingChannel
    extends DelegatingStreamChannel<Map<String, Object?>>
    implements RequestCancellation {
  _CancellingChannel(super.channel, this.onCancel);

  final void Function(RequestId id) onCancel;

  @override
  Future<void> cancelRequest(RequestId requestId) async => onCancel(requestId);
}
