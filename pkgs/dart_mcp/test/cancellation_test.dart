// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/server.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

void main() {
  test('a cancelled request gets no response on the wire', () async {
    final harness = _Harness();
    await harness.initialize();

    harness.send({
      'jsonrpc': '2.0',
      'id': 1,
      'method': CallToolRequest.methodName,
      'params':
          CallToolRequest(name: _Harness.slowToolName) as Map<String, Object?>,
    });
    await harness.server.slowToolCalled.future;

    harness.send({
      'jsonrpc': '2.0',
      'method': CancelledNotification.methodName,
      'params':
          CancelledNotification(requestId: RequestId(1), reason: 'user said so')
              as Map<String, Object?>,
    });
    await pumpEventQueue();

    // The handler is only released after the cancellation has been seen, so
    // the response it produces is the one the specification says must not go
    // out.
    harness.server.finishSlowTool.complete();
    await pumpEventQueue();

    expect(harness.framesWithId(1), isEmpty);
  });

  test('the cancellation reaches the server with its reason', () async {
    final harness = _Harness();
    await harness.initialize();
    final cancellations = <CancelledNotification>[];
    harness.server.cancellations.listen(cancellations.add);

    harness.send({
      'jsonrpc': '2.0',
      'id': 1,
      'method': CallToolRequest.methodName,
      'params':
          CallToolRequest(name: _Harness.slowToolName) as Map<String, Object?>,
    });
    await harness.server.slowToolCalled.future;
    harness.send({
      'jsonrpc': '2.0',
      'method': CancelledNotification.methodName,
      'params':
          CancelledNotification(requestId: RequestId(1), reason: 'user said so')
              as Map<String, Object?>,
    });
    await pumpEventQueue();

    expect(cancellations, hasLength(1));
    expect(cancellations.single.requestId, 1);
    expect(cancellations.single.reason, 'user said so');

    harness.server.finishSlowTool.complete();
    await pumpEventQueue();
  });

  test('a cancellation for an unknown id is ignored', () async {
    final harness = _Harness();
    await harness.initialize();
    final cancellations = <CancelledNotification>[];
    harness.server.cancellations.listen(cancellations.add);

    harness.send({
      'jsonrpc': '2.0',
      'method': CancelledNotification.methodName,
      'params':
          CancelledNotification(requestId: RequestId(404))
              as Map<String, Object?>,
    });
    harness.send({
      'jsonrpc': '2.0',
      'method': CancelledNotification.methodName,
      'params': <String, Object?>{'requestId': <String, Object?>{}},
    });
    harness.send({
      'jsonrpc': '2.0',
      'method': CancelledNotification.methodName,
      'params': <String, Object?>{},
    });
    await pumpEventQueue();

    expect(cancellations, isEmpty);
    // No error answers a notification, and an id this side never saw does not
    // poison the next request that happens to reuse it.
    expect(harness.frames.where((f) => f.containsKey('error')), isEmpty);
    expect(harness.frames.where((f) => f['id'] == 404), isEmpty);

    harness.send({
      'jsonrpc': '2.0',
      'id': 404,
      'method': ListToolsRequest.methodName,
      'params': ListToolsRequest() as Map<String, Object?>,
    });
    await pumpEventQueue();
    expect(harness.framesWithId(404), hasLength(1));
  });

  test('a cancellation that arrives after the response is ignored', () async {
    final harness = _Harness();
    await harness.initialize();
    final cancellations = <CancelledNotification>[];
    harness.server.cancellations.listen(cancellations.add);

    harness.send({
      'jsonrpc': '2.0',
      'id': 1,
      'method': ListToolsRequest.methodName,
      'params': ListToolsRequest() as Map<String, Object?>,
    });
    await pumpEventQueue();
    expect(harness.framesWithId(1), hasLength(1));

    harness.send({
      'jsonrpc': '2.0',
      'method': CancelledNotification.methodName,
      'params':
          CancelledNotification(requestId: RequestId(1))
              as Map<String, Object?>,
    });
    await pumpEventQueue();

    expect(cancellations, isEmpty);
  });

  test('progress for a cancelled request stays off the wire', () async {
    final harness = _Harness();
    await harness.initialize();

    harness.send({
      'jsonrpc': '2.0',
      'id': 1,
      'method': CallToolRequest.methodName,
      'params':
          CallToolRequest(
                name: _Harness.slowToolName,
                meta: MetaWithProgressToken(progressToken: ProgressToken('t')),
              )
              as Map<String, Object?>,
    });
    await harness.server.slowToolCalled.future;
    harness.server.notifyProgress(
      ProgressNotification(progressToken: ProgressToken('t'), progress: 1),
    );
    await pumpEventQueue();
    expect(harness.progressFrames, hasLength(1));

    harness.send({
      'jsonrpc': '2.0',
      'method': CancelledNotification.methodName,
      'params':
          CancelledNotification(requestId: RequestId(1))
              as Map<String, Object?>,
    });
    await pumpEventQueue();
    harness.server.notifyProgress(
      ProgressNotification(progressToken: ProgressToken('t'), progress: 2),
    );
    await pumpEventQueue();

    expect(harness.progressFrames, hasLength(1));

    harness.server.finishSlowTool.complete();
    await pumpEventQueue();
  });

  test(
    'progress for a live request sharing the token still goes out',
    () async {
      final harness = _Harness();
      await harness.initialize();

      for (final id in [1, 2]) {
        harness.send({
          'jsonrpc': '2.0',
          'id': id,
          'method': CallToolRequest.methodName,
          'params':
              CallToolRequest(
                    name: _Harness.slowToolName,
                    meta: MetaWithProgressToken(
                      progressToken: ProgressToken('t'),
                    ),
                  )
                  as Map<String, Object?>,
        });
      }
      await harness.server.slowToolCalled.future;

      harness.send({
        'jsonrpc': '2.0',
        'method': CancelledNotification.methodName,
        'params':
            CancelledNotification(requestId: RequestId(1))
                as Map<String, Object?>,
      });
      await pumpEventQueue();
      harness.server.notifyProgress(
        ProgressNotification(progressToken: ProgressToken('t'), progress: 1),
      );
      await pumpEventQueue();

      expect(harness.progressFrames, hasLength(1));

      harness.server.finishSlowTool.complete();
      await pumpEventQueue();

      // Only the request that was not cancelled is answered.
      expect(harness.framesWithId(1), isEmpty);
      expect(harness.framesWithId(2), hasLength(1));
    },
  );
}

/// A server on a raw JSON-RPC channel, so a test can assert on the frames
/// that do and do not reach the peer.
class _Harness {
  static const slowToolName = 'slow';

  final _toServer = StreamController<Map<String, Object?>>();
  final _fromServer = StreamController<Map<String, Object?>>();

  /// Every frame the server has written.
  final frames = <Map<String, Object?>>[];

  late final _CancellationTestServer server;

  _Harness() {
    _fromServer.stream.listen(frames.add);
    server = _CancellationTestServer(
      StreamChannel<Map<String, Object?>>.withCloseGuarantee(
        _toServer.stream,
        _fromServer.sink,
      ),
    );
    addTearDown(() async {
      if (!server.finishSlowTool.isCompleted) server.finishSlowTool.complete();
      await server.shutdown();
    });
  }

  /// Writes [frame] to the server as a peer would.
  void send(Map<String, Object?> frame) => _toServer.add(frame);

  /// The response frames the server wrote for the request [id].
  Iterable<Map<String, Object?>> framesWithId(Object id) =>
      frames.where((frame) => frame['id'] == id);

  /// The progress notifications the server wrote.
  Iterable<Map<String, Object?>> get progressFrames => frames.where(
    (frame) => frame['method'] == ProgressNotification.methodName,
  );

  /// Runs the legacy handshake with raw frames.
  Future<void> initialize() async {
    send({
      'jsonrpc': '2.0',
      'id': 0,
      'method': InitializeRequest.methodName,
      'params':
          InitializeRequest(
                protocolVersion: ProtocolVersion.v2025_11_25,
                capabilities: ClientCapabilities(),
                clientInfo: Implementation(name: 'test client', version: '1'),
              )
              as Map<String, Object?>,
    });
    send({
      'jsonrpc': '2.0',
      'method': InitializedNotification.methodName,
      'params': InitializedNotification() as Map<String, Object?>,
    });
    await server.initialized;
    frames.clear();
  }
}

/// A server with one tool whose handler the test releases by hand.
final class _CancellationTestServer extends MCPServer with ToolsSupport {
  _CancellationTestServer(super.channel)
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'cancellation test server',
          version: '1.0.0',
        ),
      );

  /// Completes when the slow tool's handler has started.
  final slowToolCalled = Completer<void>();

  /// Completed by the test to let the slow tool's handler return.
  final finishSlowTool = Completer<void>();

  @override
  FutureOr<void> initialize(MCPServerInitialization initialization) {
    registerTool(
      Tool(name: _Harness.slowToolName, inputSchema: ObjectSchema()),
      (_) async {
        if (!slowToolCalled.isCompleted) slowToolCalled.complete();
        await finishSlowTool.future;
        return CallToolResult(content: []);
      },
    );
    return super.initialize(initialization);
  }
}
