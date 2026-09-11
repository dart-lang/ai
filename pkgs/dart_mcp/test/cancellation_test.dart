// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/client.dart';
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

  test('a cancellation for an unknown id changes nothing', () async {
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

    // The specification's "ignore" is about the wire: no error response and
    // no state change. The id may name a request this side sent, so the
    // notification is still reported; the two that name no JSON-RPC id at all
    // are dropped.
    expect(cancellations, hasLength(1));
    expect(cancellations.single.requestId, 404);
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

  test('a request whose `_meta` is not an object is still answered', () async {
    final harness = _Harness();
    await harness.initialize();

    harness.send({
      'jsonrpc': '2.0',
      'id': 1,
      'method': PingRequest.methodName,
      'params': <String, Object?>{'_meta': 'oops'},
    });
    await pumpEventQueue();

    expect(harness.framesWithId(1), hasLength(1));

    // A frame the tracker could not read must not take the connection with
    // it: the next request is answered too.
    harness.send({
      'jsonrpc': '2.0',
      'id': 2,
      'method': ListToolsRequest.methodName,
      'params': ListToolsRequest() as Map<String, Object?>,
    });
    await pumpEventQueue();

    expect(harness.framesWithId(2), hasLength(1));
  });

  test('progress after a dropped response stays off the wire', () async {
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

    harness.send({
      'jsonrpc': '2.0',
      'method': CancelledNotification.methodName,
      'params':
          CancelledNotification(requestId: RequestId(1))
              as Map<String, Object?>,
    });
    await pumpEventQueue();

    // Releasing the handler drops the response; the specification forbids any
    // further message for the request, so the token stays suppressed after
    // that.
    harness.server.finishSlowTool.complete();
    await pumpEventQueue();
    expect(harness.framesWithId(1), isEmpty);

    harness.server.notifyProgress(
      ProgressNotification(progressToken: ProgressToken('t'), progress: 9),
    );
    await pumpEventQueue();

    expect(harness.progressFrames, isEmpty);
  });

  test('a reused token goes out again for a live request', () async {
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
    harness.send({
      'jsonrpc': '2.0',
      'method': CancelledNotification.methodName,
      'params':
          CancelledNotification(requestId: RequestId(1))
              as Map<String, Object?>,
    });
    await pumpEventQueue();
    harness.server.finishSlowTool.complete();
    await pumpEventQueue();

    // The peer asks again under the same token, and that request is in
    // flight. Suppressing the token for the cancelled request must not
    // silence the new one.
    harness.send({
      'jsonrpc': '2.0',
      'id': 2,
      'method': CallToolRequest.methodName,
      'params':
          CallToolRequest(
                name: _Harness.otherSlowToolName,
                meta: MetaWithProgressToken(progressToken: ProgressToken('t')),
              )
              as Map<String, Object?>,
    });
    await harness.server.otherSlowToolCalled.future;
    harness.server.notifyProgress(
      ProgressNotification(progressToken: ProgressToken('t'), progress: 1),
    );
    await pumpEventQueue();

    expect(harness.progressFrames, hasLength(1));

    harness.server.finishOtherSlowTool.complete();
    await pumpEventQueue();
    expect(harness.framesWithId(2), hasLength(1));
  });

  test(
    'a cancellation that arrives after the response changes nothing',
    () async {
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

      // The race the specification asks both parties to handle: the answer was
      // already on the wire, so nothing is taken back, and the notification is
      // reported like any other.
      expect(cancellations, hasLength(1));
      expect(harness.framesWithId(1), hasLength(1));
      expect(harness.frames.where((f) => f.containsKey('error')), isEmpty);

      // A later request reusing that id is answered, so the cancellation left
      // nothing behind.
      harness.send({
        'jsonrpc': '2.0',
        'id': 1,
        'method': PingRequest.methodName,
        'params': PingRequest() as Map<String, Object?>,
      });
      await pumpEventQueue();
      expect(harness.framesWithId(1), hasLength(2));
    },
  );

  test('a client sees the cancellation a server sends it', () async {
    final harness = _ClientHarness(maxRetainedCancellations: 1);
    final cancellations = <CancelledNotification>[];
    harness.connection.cancellations.listen(cancellations.add);

    // The 2026-07-28 revision has the server cancel the `subscriptions/listen`
    // request whose stream it tears down, and that notification names a
    // request the client sent, not one it is answering.
    harness.send({
      'jsonrpc': '2.0',
      'method': CancelledNotification.methodName,
      'params':
          CancelledNotification(
                requestId: RequestId(7),
                reason: 'subscription torn down',
              )
              as Map<String, Object?>,
    });
    await pumpEventQueue();

    expect(cancellations, hasLength(1));
    expect(cancellations.single.requestId, 7);
    expect(cancellations.single.reason, 'subscription torn down');
  });

  test('a client honours the bound its constructor was given', () async {
    // One retained token on the client side, reached through
    // `MCPClient.connectServer`, so the second cancellation evicts the first.
    final harness = _ClientHarness(maxRetainedCancellations: 1);

    await harness.cancelListRoots(1, 't1');
    await harness.cancelListRoots(2, 't2');

    harness.connection.notifyProgress(
      ProgressNotification(progressToken: ProgressToken('t1'), progress: 1),
    );
    harness.connection.notifyProgress(
      ProgressNotification(progressToken: ProgressToken('t2'), progress: 2),
    );
    await pumpEventQueue();

    expect(harness.progressFrames, hasLength(1));
    expect(_progressTokenOf(harness.progressFrames.single), 't1');
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

  test('an evicted token lets progress through again', () async {
    // One retained token, so the second cancellation evicts the first one.
    final harness = _Harness(maxRetainedCancellations: 1);
    await harness.initialize();

    await harness.cancelGated(1, 't1');
    await harness.cancelGated(2, 't2');

    harness.server.notifyProgress(
      ProgressNotification(progressToken: ProgressToken('t1'), progress: 1),
    );
    harness.server.notifyProgress(
      ProgressNotification(progressToken: ProgressToken('t2'), progress: 2),
    );
    await pumpEventQueue();

    // The bound is what the connection forgets, so the evicted token is no
    // longer suppressed and the retained one still is.
    expect(harness.progressFrames, hasLength(1));
    expect(_progressTokenOf(harness.progressFrames.single), 't1');
  });

  test('a cancellation re-touches a retained token', () async {
    // Two retained tokens, and four cancellations over three tokens, so which
    // token survives says where a repeat lands in the eviction order.
    final harness = _Harness(maxRetainedCancellations: 2);
    await harness.initialize();

    await harness.cancelGated(1, 't1');
    await harness.cancelGated(2, 't2');
    await harness.cancelGated(3, 't1');
    await harness.cancelGated(4, 't3');

    for (final token in ['t1', 't2', 't3']) {
      harness.server.notifyProgress(
        ProgressNotification(progressToken: ProgressToken(token), progress: 1),
      );
    }
    await pumpEventQueue();

    // `t1` was cancelled again after `t2`, so `t2` is the oldest and the one
    // the fourth cancellation evicts.
    expect(harness.progressFrames, hasLength(1));
    expect(_progressTokenOf(harness.progressFrames.single), 't2');
  });
}

/// The progress token [frame] carries, for a progress notification frame.
Object? _progressTokenOf(Map<String, Object?> frame) =>
    (frame['params'] as Map<String, Object?>?)?['progressToken'];

/// A client on a raw JSON-RPC channel, built the way an embedder builds one,
/// so a test can assert on the frames that do and do not reach the server.
class _ClientHarness {
  final _toClient = StreamController<Map<String, Object?>>();
  final _fromClient = StreamController<Map<String, Object?>>();

  /// Every frame the client has written.
  final frames = <Map<String, Object?>>[];

  late final _CancellationTestClient client;

  /// The connection [client] opened, which is what the server talks to.
  late final ServerConnection connection;

  _ClientHarness({required int maxRetainedCancellations}) {
    _fromClient.stream.listen(frames.add);
    client = _CancellationTestClient(
      maxRetainedCancellations: maxRetainedCancellations,
    );
    connection = client.connectServer(
      StreamChannel<Map<String, Object?>>.withCloseGuarantee(
        _toClient.stream,
        _fromClient.sink,
      ),
    );
    addTearDown(() async {
      if (!client.finishListRoots.isCompleted) {
        client.finishListRoots.complete();
      }
      await client.shutdown();
    });
  }

  /// Writes [frame] to the client as a server would.
  void send(Map<String, Object?> frame) => _toClient.add(frame);

  /// The response frames the client wrote for the request [id].
  Iterable<Map<String, Object?>> framesWithId(Object id) =>
      frames.where((frame) => frame['id'] == id);

  /// The progress notifications the client wrote.
  Iterable<Map<String, Object?>> get progressFrames => frames.where(
    (frame) => frame['method'] == ProgressNotification.methodName,
  );

  /// Sends the client a `roots/list` request as [id] under [token], cancels it
  /// while its handler is running, and releases the handler.
  ///
  /// A client answering a server's request is the role that reaches
  /// [MCPClient.connectServer], so this fills the retention bound that call
  /// passed on.
  Future<void> cancelListRoots(Object id, String token) async {
    client.listRootsCalled = Completer<void>();
    final release = client.finishListRoots = Completer<void>();
    send({
      'jsonrpc': '2.0',
      'id': id,
      'method': ListRootsRequest.methodName,
      'params': <String, Object?>{
        '_meta': <String, Object?>{'progressToken': token},
      },
    });
    await client.listRootsCalled.future;
    send({
      'jsonrpc': '2.0',
      'method': CancelledNotification.methodName,
      'params':
          CancelledNotification(requestId: RequestId(id))
              as Map<String, Object?>,
    });
    await pumpEventQueue();
    release.complete();
    await pumpEventQueue();
    expect(framesWithId(id), isEmpty);
  }
}

/// A client whose `roots/list` handler the test releases by hand.
final class _CancellationTestClient extends MCPClient with RootsSupport {
  _CancellationTestClient({required super.maxRetainedCancellations})
    : super(Implementation(name: 'cancellation test client', version: '1.0.0'));

  /// Completes when the roots handler has started.
  ///
  /// Replaced by [_ClientHarness.cancelListRoots] before each request it
  /// drives.
  Completer<void> listRootsCalled = Completer<void>();

  /// Completed by the test to let the roots handler return.
  Completer<void> finishListRoots = Completer<void>();

  @override
  Future<ListRootsResult> handleListRoots([ListRootsRequest? request]) async {
    if (!listRootsCalled.isCompleted) listRootsCalled.complete();
    await finishListRoots.future;
    return super.handleListRoots(request);
  }
}

/// A server on a raw JSON-RPC channel, so a test can assert on the frames
/// that do and do not reach the peer.
class _Harness {
  static const slowToolName = 'slow';
  static const otherSlowToolName = 'other slow';
  static const gatedToolName = 'gated';

  final _toServer = StreamController<Map<String, Object?>>();
  final _fromServer = StreamController<Map<String, Object?>>();

  /// Every frame the server has written.
  final frames = <Map<String, Object?>>[];

  late final _CancellationTestServer server;

  _Harness({int? maxRetainedCancellations}) {
    _fromServer.stream.listen(frames.add);
    final channel = StreamChannel<Map<String, Object?>>.withCloseGuarantee(
      _toServer.stream,
      _fromServer.sink,
    );
    server =
        maxRetainedCancellations == null
            ? _CancellationTestServer(channel)
            : _CancellationTestServer(
              channel,
              maxRetainedCancellations: maxRetainedCancellations,
            );
    addTearDown(() async {
      if (!server.finishSlowTool.isCompleted) server.finishSlowTool.complete();
      if (!server.finishOtherSlowTool.isCompleted) {
        server.finishOtherSlowTool.complete();
      }
      if (!server.finishGatedTool.isCompleted) {
        server.finishGatedTool.complete();
      }
      await server.shutdown();
    });
  }

  /// Calls the gated tool as request [id] under [token], cancels it while its
  /// handler is running, and releases the handler.
  ///
  /// The dropped response is what makes the connection retain [token], so
  /// this is one step of filling the retention bound.
  Future<void> cancelGated(Object id, String token) async {
    server.gatedToolCalled = Completer<void>();
    final release = server.finishGatedTool = Completer<void>();
    send({
      'jsonrpc': '2.0',
      'id': id,
      'method': CallToolRequest.methodName,
      'params':
          CallToolRequest(
                name: gatedToolName,
                meta: MetaWithProgressToken(
                  progressToken: ProgressToken(token),
                ),
              )
              as Map<String, Object?>,
    });
    await server.gatedToolCalled.future;
    send({
      'jsonrpc': '2.0',
      'method': CancelledNotification.methodName,
      'params':
          CancelledNotification(requestId: RequestId(id))
              as Map<String, Object?>,
    });
    await pumpEventQueue();
    release.complete();
    await pumpEventQueue();
    expect(framesWithId(id), isEmpty);
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
  _CancellationTestServer(super.channel, {super.maxRetainedCancellations})
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

  /// Completes when the second slow tool's handler has started.
  ///
  /// A second tool with its own releaser lets a test hold one request while
  /// another one has already been answered.
  final otherSlowToolCalled = Completer<void>();

  /// Completed by the test to let the second slow tool's handler return.
  final finishOtherSlowTool = Completer<void>();

  /// Completes when the gated tool's handler has started.
  ///
  /// Replaced by [_Harness.cancelGated] before each call it drives, so one
  /// tool can serve a sequence of cancelled requests.
  Completer<void> gatedToolCalled = Completer<void>();

  /// Completed by the test to let the gated tool's current call return.
  Completer<void> finishGatedTool = Completer<void>();

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
    registerTool(
      Tool(name: _Harness.otherSlowToolName, inputSchema: ObjectSchema()),
      (_) async {
        if (!otherSlowToolCalled.isCompleted) otherSlowToolCalled.complete();
        await finishOtherSlowTool.future;
        return CallToolResult(content: []);
      },
    );
    registerTool(
      Tool(name: _Harness.gatedToolName, inputSchema: ObjectSchema()),
      (_) async {
        if (!gatedToolCalled.isCompleted) gatedToolCalled.complete();
        await finishGatedTool.future;
        return CallToolResult(content: []);
      },
    );
    return super.initialize(initialization);
  }
}
