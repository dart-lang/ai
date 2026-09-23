// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/server.dart';
import 'package:json_rpc_2/error_code.dart' as error_code;
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

  test(
    'an async handler with omitted params keeps cancellation context',
    () async {
      final harness = _Harness();
      await harness.initialize();

      harness.send({
        'jsonrpc': '2.0',
        'id': 1,
        'method': _Harness.parameterlessMethod,
      });
      await harness.server.parameterlessCalled.future;
      harness.cancel(1);
      await pumpEventQueue();
      harness.server.finishParameterless.complete();
      await pumpEventQueue();

      expect(harness.framesWithId(1), isEmpty);
      expect(
        harness.frames.where(
          (frame) => frame['method'] == LoggingMessageNotification.methodName,
        ),
        isEmpty,
      );
      expect(
        harness.frames.where(
          (frame) => frame['method'] == PingRequest.methodName,
        ),
        isEmpty,
      );

      harness.server.parameterlessCalled = Completer<void>();
      harness.server.finishParameterless = Completer<void>();
      harness.send({
        'jsonrpc': '2.0',
        'id': 2,
        'method': _Harness.parameterlessMethod,
      });
      await harness.server.parameterlessCalled.future;
      harness.server.finishParameterless.complete();
      await pumpEventQueue();

      final sentPings = harness.frames.where(
        (frame) => frame['method'] == PingRequest.methodName,
      );
      expect(sentPings, hasLength(1));
      harness.send({
        'jsonrpc': '2.0',
        'id': sentPings.single['id'],
        'result': EmptyResult() as Map<String, Object?>,
      });
      await pumpEventQueue();

      expect(harness.framesWithId(2), hasLength(1));
      expect(harness.framesWithId(2).single, contains('result'));
      expect(harness.framesWithId(2).single, isNot(contains('error')));
      expect(
        harness.frames
            .where(
              (frame) =>
                  frame['method'] == LoggingMessageNotification.methodName,
            )
            .map((frame) => (frame['params'] as Map<String, Object?>)['data']),
        ['parameterless completed'],
      );
    },
  );

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

  test('a cancellation for an unknown ID changes nothing', () async {
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

    // The specification's "ignore" is about the wire, with no error response
    // and no state change. An outgoing request can carry that ID, and the
    // notification is reported either way. The two naming no JSON-RPC ID at
    // all are dropped.
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

  test('a request with a non-object `_meta` is still answered', () async {
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

  test('a general metadata map keeps active request progress', () async {
    final harness = _Harness();
    await harness.initialize();

    harness.send({
      'jsonrpc': '2.0',
      'id': 1,
      'method': CallToolRequest.methodName,
      'params': <Object?, Object?>{
        'name': _Harness.slowToolName,
        '_meta': <Object?, Object?>{'progressToken': 'general'},
      },
    });
    await harness.server.slowToolCalled.future;

    harness.server.notifyProgress(
      ProgressNotification(
        progressToken: ProgressToken('general'),
        progress: 1,
      ),
    );
    await pumpEventQueue();

    expect(harness.progressFrames, hasLength(1));

    harness.server.finishSlowTool.complete();
    await pumpEventQueue();
  });

  test('only active request progress reaches the wire', () async {
    final harness = _Harness();
    await harness.initialize();

    harness.server.notifyProgress(
      ProgressNotification(
        progressToken: ProgressToken('unknown'),
        progress: 1,
      ),
    );
    await pumpEventQueue();
    expect(harness.progressFrames, isEmpty);

    harness.sendSlowRequest(1, 'active');
    await harness.server.slowToolCalled.future;
    harness.server.notifyProgress(
      ProgressNotification(progressToken: ProgressToken('active'), progress: 2),
    );
    await pumpEventQueue();
    expect(harness.progressFrames, hasLength(1));

    harness.server.finishSlowTool.complete();
    await pumpEventQueue();
    expect(harness.framesWithId(1), hasLength(1));

    harness.server.notifyProgress(
      ProgressNotification(progressToken: ProgressToken('active'), progress: 3),
    );
    await pumpEventQueue();
    expect(harness.progressFrames, hasLength(1));
  });

  test('non-string parameter keys do not close the connection', () async {
    final harness = _Harness();
    await harness.initialize();

    harness.send({
      'jsonrpc': '2.0',
      'id': 1,
      'method': CallToolRequest.methodName,
      'params': <Object, Object?>{1: 'not a JSON object key'},
    });
    await pumpEventQueue();

    expect(harness.server.isActive, isTrue);
    expect(harness.framesWithId(1), hasLength(1));
    expect(harness.framesWithId(1).single, contains('error'));
    expect(harness.framesWithId(1).single, isNot(contains('result')));

    harness.send({
      'jsonrpc': '2.0',
      'id': 2,
      'method': PingRequest.methodName,
      'params': PingRequest() as Map<String, Object?>,
    });
    await pumpEventQueue();

    expect(harness.framesWithId(2), hasLength(1));
    expect(harness.framesWithId(2).single, contains('result'));
    expect(harness.framesWithId(2).single, isNot(contains('error')));
  });

  test(
    'an unusable cancellation ID is logged and a missing one is not',
    () async {
      final harness = _Harness();
      await harness.initialize();

      harness.cancel(<Object?>['bad']);
      harness.send({
        'jsonrpc': '2.0',
        'method': CancelledNotification.methodName,
        'params': <String, Object?>{},
      });
      await pumpEventQueue();

      expect(harness.diagnostics, hasLength(1));
      expect(harness.diagnostics.single, contains('["bad"]'));
      expect(harness.diagnostics.single, contains('not a JSON-RPC ID'));
    },
  );

  test('invalid request IDs leave no progress owner', () async {
    final harness = _Harness();
    await harness.initialize();

    for (final (index, id)
        in [
          <String, Object?>{'bad': 1},
          <Object?>['bad'],
        ].indexed) {
      final token = 'invalid-$index';
      harness.send({
        'jsonrpc': '2.0',
        'id': id,
        'method': CallToolRequest.methodName,
        'params':
            CallToolRequest(
                  name: _Harness.slowToolName,
                  meta: MetaWithProgressToken(
                    progressToken: ProgressToken(token),
                  ),
                )
                as Map<String, Object?>,
      });
      await pumpEventQueue();
      harness.cancel(id);
      harness.server.notifyProgress(
        ProgressNotification(progressToken: ProgressToken(token), progress: 1),
      );
    }
    await pumpEventQueue();

    final invalidIdErrors = harness.frames.where(
      (frame) => frame['id'] == null && frame.containsKey('error'),
    );
    expect(invalidIdErrors, hasLength(2));
    expect(
      invalidIdErrors.map(
        (frame) => (frame['error'] as Map<String, Object?>)['code'],
      ),
      everyElement(error_code.INVALID_REQUEST),
    );
    expect(harness.progressFrames, isEmpty);

    harness.sendSlowRequest(1, 'valid');
    await harness.server.slowToolCalled.future;
    harness.server.notifyProgress(
      ProgressNotification(progressToken: ProgressToken('valid'), progress: 1),
    );
    await pumpEventQueue();
    expect(harness.progressFrames, hasLength(1));

    harness.server.finishSlowTool.complete();
    await pumpEventQueue();
    expect(harness.framesWithId(1), hasLength(1));
  });

  test('a malformed request cannot take a live token', () async {
    final harness = _Harness();
    await harness.initialize();

    harness.send({
      'jsonrpc': '2.0',
      'id': 1,
      'method': CallToolRequest.methodName,
      'params':
          CallToolRequest(
                name: _Harness.slowToolName,
                meta: MetaWithProgressToken(
                  progressToken: ProgressToken('shared'),
                ),
              )
              as Map<String, Object?>,
    });
    await harness.server.slowToolCalled.future;

    harness.server.notifyProgress(
      ProgressNotification(progressToken: ProgressToken('shared'), progress: 1),
    );
    await pumpEventQueue();
    expect(harness.progressFrames, hasLength(1));

    // The server never dispatches this one, so it owns nothing. Disowning the
    // token here would drop the progress of the request still running under it.
    harness.send({
      'jsonrpc': '2.0',
      'id': <Object?>['not an id'],
      'method': CallToolRequest.methodName,
      'params':
          CallToolRequest(
                name: _Harness.slowToolName,
                meta: MetaWithProgressToken(
                  progressToken: ProgressToken('shared'),
                ),
              )
              as Map<String, Object?>,
    });
    await pumpEventQueue();

    harness.server.notifyProgress(
      ProgressNotification(progressToken: ProgressToken('shared'), progress: 2),
    );
    await pumpEventQueue();
    expect(
      harness.progressFrames,
      hasLength(2),
      reason: 'the live request still owns the token',
    );

    harness.server.finishSlowTool.complete();
    await pumpEventQueue();
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

  test('a live request takes over a token from a cancelled one', () async {
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

    // The cancelled handler is still running, so request 1 still holds the
    // token when request 2 declares it. The live request owns it from here.
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

    harness.server.finishSlowTool.complete();
    harness.server.finishOtherSlowTool.complete();
    await pumpEventQueue();
    expect(harness.framesWithId(1), isEmpty);
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

      // The answer was already on the wire in this race, and nothing is
      // taken back. The notification is reported like any other.
      expect(cancellations, hasLength(1));
      expect(harness.framesWithId(1), hasLength(1));
      expect(harness.frames.where((f) => f.containsKey('error')), isEmpty);

      // A later request reusing that ID is answered, so the cancellation left
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

  test('a malformed method does not close the connection', () async {
    final harness = _Harness();
    await harness.initialize();

    harness.send({
      'jsonrpc': '2.0',
      'method': 42,
      'params': <String, Object?>{},
    });
    await pumpEventQueue();
    expect(harness.server.isActive, isTrue);

    harness.send({
      'jsonrpc': '2.0',
      'id': 1,
      'method': PingRequest.methodName,
      'params': PingRequest() as Map<String, Object?>,
    });
    await pumpEventQueue();
    expect(harness.framesWithId(1), hasLength(1));
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

  test('cancellation suppresses only its handler notifications', () async {
    final harness = _Harness();
    await harness.initialize();
    harness.server.logAfterTool = true;
    harness.server.requestAfterSlowTool = true;

    harness.sendSlowRequestWithGeneralParams(1, 'cancelled');
    harness.sendOtherSlowRequest(2, 'active');
    await Future.wait([
      harness.server.slowToolCalled.future,
      harness.server.otherSlowToolCalled.future,
    ]);

    harness.cancel(1);
    await pumpEventQueue();
    harness.server.finishSlowTool.complete();
    harness.server.finishOtherSlowTool.complete();
    await pumpEventQueue();

    var logs = harness.frames.where(
      (frame) => frame['method'] == LoggingMessageNotification.methodName,
    );
    expect(logs, hasLength(1));
    expect(
      logs.map((frame) => (frame['params'] as Map<String, Object?>)['data']),
      ['other completed'],
    );
    expect(harness.framesWithId(1), isEmpty);
    expect(harness.framesWithId(2), hasLength(1));
    expect(
      harness.frames.where(
        (frame) => frame['method'] == PingRequest.methodName,
      ),
      isEmpty,
    );

    harness.server.finishLateLogs.complete();
    await pumpEventQueue();
    logs = harness.frames.where(
      (frame) => frame['method'] == LoggingMessageNotification.methodName,
    );
    expect(logs, hasLength(2));
    expect(
      logs.map((frame) => (frame['params'] as Map<String, Object?>)['data']),
      ['other completed', 'other completed after response'],
    );

    final ping = harness.server.sendRequest<EmptyResult>(
      PingRequest.methodName,
    );
    await pumpEventQueue();
    final sentPing = harness.frames.singleWhere(
      (frame) => frame['method'] == PingRequest.methodName,
    );
    harness.send({
      'jsonrpc': '2.0',
      'id': sentPing['id'],
      'result': EmptyResult() as Map<String, Object?>,
    });
    expect(await ping, isA<EmptyResult>());
  });

  test('cancelling past any bound keeps the connection up', () async {
    final harness = _Harness();
    await harness.initialize();

    await harness.cancelGated(1, 't1');
    await harness.cancelGated(2, 't2');
    await harness.cancelGated(3, 't3');

    expect(harness.server.isActive, isTrue);
    expect(harness.framesWithId(1), isEmpty);
    expect(harness.framesWithId(2), isEmpty);
    expect(harness.framesWithId(3), isEmpty);
  });

  test('a repeated cancellation is harmless', () async {
    final harness = _Harness();
    await harness.initialize();

    harness.sendSlowRequest(1, 't1');
    await harness.server.slowToolCalled.future;
    harness.cancel(1);
    harness.cancel(1);
    await pumpEventQueue();

    expect(harness.server.isActive, isTrue);
    harness.server.finishSlowTool.complete();
    await pumpEventQueue();
    expect(harness.framesWithId(1), isEmpty);
  });

  test('two cancelled requests both go quiet on the wire', () async {
    final harness = _Harness();
    await harness.initialize();

    harness.sendSlowRequest(1, 't1');
    harness.sendOtherSlowRequest(2, 't2');
    await Future.wait([
      harness.server.slowToolCalled.future,
      harness.server.otherSlowToolCalled.future,
    ]);
    harness.cancel(1);
    await pumpEventQueue();
    expect(harness.server.isActive, isTrue);

    harness.cancel(2);
    harness.server.finishSlowTool.complete();
    harness.server.finishOtherSlowTool.complete();
    await pumpEventQueue();
    harness.server.notifyProgress(
      ProgressNotification(progressToken: ProgressToken('t1'), progress: 1),
    );
    harness.server.notifyProgress(
      ProgressNotification(progressToken: ProgressToken('t2'), progress: 1),
    );
    await pumpEventQueue();

    expect(harness.framesWithId(1), isEmpty);
    expect(harness.framesWithId(2), isEmpty);
    expect(harness.progressFrames, isEmpty);
  });

  test(
    'a cancelled subscription ends instead of waiting for shutdown',
    () async {
      final harness = _SubscriptionHarness();
      await harness.initialize();

      harness.listen(1);
      await pumpEventQueue();
      harness.listen(2);
      await pumpEventQueue();
      expect(harness.acknowledgements, hasLength(2));

      harness.cancel(1);
      await pumpEventQueue();
      harness.cancel(2);
      await pumpEventQueue();

      // Ending each cancelled subscription lets its response leave the handler.
      // A subscription that waited for shutdown instead would hold its request
      // open for the life of the connection.
      expect(harness.server.isActive, isTrue);
      expect(harness.framesWithId(1), isEmpty);
      expect(harness.framesWithId(2), isEmpty);
    },
  );

  test('resource updates follow active listen owners exactly once', () async {
    final harness = _SubscriptionHarness();
    await harness.initialize();

    harness.listen(
      1,
      notifications: SubscriptionFilter(
        resourceSubscriptions: [_SubscriptionHarness.resource.uri],
      ),
    );
    await pumpEventQueue();
    harness.cancel(1);
    await pumpEventQueue();
    harness.updateResource();
    await pumpEventQueue();
    expect(
      harness.resourceUpdates,
      isEmpty,
      reason: 'a cancelled listen is not an active update owner',
    );

    harness.listen(
      2,
      notifications: SubscriptionFilter(
        resourceSubscriptions: [_SubscriptionHarness.resource.uri],
      ),
    );
    await pumpEventQueue();
    harness.listen(
      3,
      notifications: SubscriptionFilter(
        resourceSubscriptions: [_SubscriptionHarness.resource.uri],
      ),
    );
    await pumpEventQueue();
    expect(harness.acknowledgements, hasLength(3));

    harness.updateResource();
    await pumpEventQueue();
    expect(harness.resourceUpdates, hasLength(1));

    harness.cancel(2);
    await pumpEventQueue();
    harness.updateResource();
    await pumpEventQueue();
    expect(
      harness.resourceUpdates,
      hasLength(2),
      reason: 'the remaining active owner keeps exactly one wire update',
    );

    harness.cancel(3);
    await pumpEventQueue();
    harness.updateResource();
    await pumpEventQueue();
    expect(
      harness.resourceUpdates,
      hasLength(2),
      reason: 'no update is sent after the last active owner is cancelled',
    );
  });

  test('legacy and listen owners share a resource subscription', () async {
    final harness = _SubscriptionHarness();
    await harness.initialize();
    final uri = _SubscriptionHarness.resource.uri;

    await harness.server.subscribeResource(SubscribeRequest(uri: uri));
    harness.listen(
      1,
      notifications: SubscriptionFilter(resourceSubscriptions: [uri]),
    );
    await pumpEventQueue();
    expect(harness.acknowledgements, hasLength(1));

    await harness.server.unsubscribeResource(UnsubscribeRequest(uri: uri));
    harness.updateResource();
    await pumpEventQueue();
    expect(harness.resourceUpdates, hasLength(1));

    harness.cancel(1);
    await pumpEventQueue();
    harness.updateResource();
    await pumpEventQueue();
    expect(harness.resourceUpdates, hasLength(1));

    await harness.server.subscribeResource(SubscribeRequest(uri: uri));
    harness.listen(
      2,
      notifications: SubscriptionFilter(resourceSubscriptions: [uri]),
    );
    await pumpEventQueue();
    expect(harness.acknowledgements, hasLength(2));

    harness.cancel(2);
    await pumpEventQueue();
    harness.updateResource();
    await pumpEventQueue();
    expect(harness.resourceUpdates, hasLength(2));

    await harness.server.unsubscribeResource(UnsubscribeRequest(uri: uri));
    harness.updateResource();
    await pumpEventQueue();
    expect(harness.resourceUpdates, hasLength(2));
  });

  test('an inactive registered owner keeps its resource stream', () async {
    final harness = _SubscriptionHarness();
    await harness.initialize();
    final uri = _SubscriptionHarness.resource.uri;
    final startsBeforeSubscribe = harness.server.resourceStreamStarts;
    await harness.server.subscribeResource(SubscribeRequest(uri: uri));
    harness.listen(
      1,
      notifications: SubscriptionFilter(resourceSubscriptions: [uri]),
    );
    await pumpEventQueue();
    expect(harness.acknowledgements, hasLength(1));
    expect(harness.server.resourceStreamStarts, startsBeforeSubscribe + 1);

    final stoppedLegacy = Completer<void>();
    Future<EmptyResult>? stopping;
    final cancellation = harness.server.cancellations.listen((_) {
      stopping = harness.server.unsubscribeResource(
        UnsubscribeRequest(uri: uri),
      );
      harness.server.subscribeResource(SubscribeRequest(uri: uri));
      stoppedLegacy.complete();
    });
    addTearDown(cancellation.cancel);
    harness.cancel(1);
    await stoppedLegacy.future;
    expect(harness.server.resourceStreamStarts, startsBeforeSubscribe + 1);
    await stopping;
    await pumpEventQueue();
    await harness.server.unsubscribeResource(UnsubscribeRequest(uri: uri));
  });

  test('a cancelled handshake still notifies list changes', () async {
    final harness = _Harness();
    final release = harness.server.holdInitialize = Completer<void>();
    harness.sendInitialize(0);
    await harness.server.initializeCalled.future;

    // The cancellation arrives while the handshake is still in its handler, so
    // the mixins open their streams under a request that is already cancelled.
    harness.cancel(0);
    await pumpEventQueue();
    release.complete();
    await harness.finishInitialize();
    expect(
      harness.framesWithId(0),
      isEmpty,
      reason: 'the cancelled handshake gets no response',
    );

    harness.server.addResource(
      Resource(name: 'watched', uri: 'file:///watched'),
      (_) => ReadResourceResult(contents: const []),
    );
    await pumpEventQueue();
    expect(
      harness.listChanges,
      hasLength(1),
      reason:
          'a stream that outlives the request that opened it belongs to '
          'the connection',
    );
  });
}

/// A server on a raw JSON-RPC channel, so a test can assert on the frames
/// that do and do not reach the peer.
class _Harness {
  static const slowToolName = 'slow';
  static const otherSlowToolName = 'other slow';
  static const gatedToolName = 'gated';
  static const parameterlessMethod = 'test/parameterless';

  final _toServer = StreamController<Map<String, Object?>>();
  final _fromServer = StreamController<Map<String, Object?>>();

  /// Every frame the server has written.
  final frames = <Map<String, Object?>>[];

  late final _CancellationTestServer server;

  _Harness() {
    _fromServer.stream.listen(frames.add);
    final channel = StreamChannel<Map<String, Object?>>.withCloseGuarantee(
      _toServer.stream,
      _fromServer.sink,
    );
    final logSink = _ListSink(protocolLog);
    server = _CancellationTestServer(channel, protocolLogSink: logSink);
    addTearDown(() async {
      if (!server.finishSlowTool.isCompleted) server.finishSlowTool.complete();
      if (!server.finishOtherSlowTool.isCompleted) {
        server.finishOtherSlowTool.complete();
      }
      if (!server.finishGatedTool.isCompleted) {
        server.finishGatedTool.complete();
      }
      if (!server.finishParameterless.isCompleted) {
        server.finishParameterless.complete();
      }
      if (!server.finishLateLogs.isCompleted) server.finishLateLogs.complete();
      await server.shutdown();
    });
  }

  /// Everything this connection wrote to its protocol log.
  final protocolLog = <String>[];

  /// The protocol log entries this package wrote about a message.
  Iterable<String> get diagnostics =>
      protocolLog.where((l) => l.startsWith('!!!'));

  /// Sends a request to the slow tool under [token].
  void sendSlowRequest(Object id, String token) =>
      _sendToolRequest(id, slowToolName, token);

  /// Sends the slow request in a generally typed Map with string keys.
  void sendSlowRequestWithGeneralParams(Object id, String token) {
    final typed =
        CallToolRequest(
              name: slowToolName,
              meta: MetaWithProgressToken(progressToken: ProgressToken(token)),
            )
            as Map<String, Object?>;
    send({
      'jsonrpc': '2.0',
      'id': id,
      'method': CallToolRequest.methodName,
      'params': Map<Object, Object?>.from(typed),
    });
  }

  /// Sends a request to the other slow tool under [token].
  void sendOtherSlowRequest(Object id, String token) =>
      _sendToolRequest(id, otherSlowToolName, token);

  /// Sends a tool request with [id], [name], and [token].
  void _sendToolRequest(Object id, String name, String token) {
    send({
      'jsonrpc': '2.0',
      'id': id,
      'method': CallToolRequest.methodName,
      'params':
          CallToolRequest(
                name: name,
                meta: MetaWithProgressToken(
                  progressToken: ProgressToken(token),
                ),
              )
              as Map<String, Object?>,
    });
  }

  /// Cancels request [id].
  void cancel(Object id) {
    send({
      'jsonrpc': '2.0',
      'method': CancelledNotification.methodName,
      'params':
          CancelledNotification(requestId: RequestId(id))
              as Map<String, Object?>,
    });
  }

  /// Calls the gated tool as request [id] under [token], cancels it while its
  /// handler is running, and releases the handler.
  ///
  /// The response is observed before the next call, releasing the bound slot.
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

  /// The resource list-changed notifications the server wrote.
  Iterable<Map<String, Object?>> get listChanges => frames.where(
    (frame) => frame['method'] == ResourceListChangedNotification.methodName,
  );

  /// Runs the legacy handshake with raw frames.
  Future<void> initialize() async {
    sendInitialize(0);
    await finishInitialize();
    frames.clear();
  }

  /// Sends the legacy `initialize` request as [id].
  void sendInitialize(Object id) {
    send({
      'jsonrpc': '2.0',
      'id': id,
      'method': InitializeRequest.methodName,
      'params':
          InitializeRequest(
                protocolVersion: ProtocolVersion.v2025_11_25,
                capabilities: ClientCapabilities(),
                clientInfo: Implementation(name: 'test client', version: '1'),
              )
              as Map<String, Object?>,
    });
  }

  /// Accepts the handshake and waits for the server to be ready to serve.
  Future<void> finishInitialize() async {
    send({
      'jsonrpc': '2.0',
      'method': InitializedNotification.methodName,
      'params': InitializedNotification() as Map<String, Object?>,
    });
    await server.initialized;
  }
}

/// A server with one tool the test releases by hand.
/// Collects protocol log entries into [target].
final class _ListSink implements Sink<String> {
  _ListSink(this.target);

  final List<String> target;

  @override
  void add(String data) => target.add(data);

  @override
  void close() {}
}

final class _CancellationTestServer extends MCPServer
    with ToolsSupport, LoggingSupport, ResourcesSupport {
  _CancellationTestServer(super.channel, {super.protocolLogSink})
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

  /// Completes when the handler for a request without `params` starts.
  Completer<void> parameterlessCalled = Completer<void>();

  /// Completed by the test to let the request without `params` return.
  Completer<void> finishParameterless = Completer<void>();

  /// Whether the slow handlers log after their manually controlled wait.
  bool logAfterTool = false;

  /// Whether the slow handler starts an outgoing request after its wait.
  bool requestAfterSlowTool = false;

  /// Completed after the test has observed the handlers' responses.
  final finishLateLogs = Completer<void>();

  /// Completes once the handshake has reached its handler.
  final initializeCalled = Completer<void>();

  /// Completed by the test to let the handshake register the mixins.
  ///
  /// A test that cancels the handshake first needs the request to still be in
  /// flight when the cancellation arrives.
  Completer<void>? holdInitialize;

  @override
  Duration get resourceUpdateThrottleDelay => Duration.zero;

  @override
  Future<void> initialize(MCPServerInitialization initialization) async {
    if (!initializeCalled.isCompleted) initializeCalled.complete();
    registerRequestHandler<PingRequest?, EmptyResult>(
      _Harness.parameterlessMethod,
      ([PingRequest? _]) async {
        if (!parameterlessCalled.isCompleted) parameterlessCalled.complete();
        await finishParameterless.future;
        log(LoggingLevel.error, 'parameterless completed');
        await sendRequest<EmptyResult>(PingRequest.methodName);
        return EmptyResult();
      },
    );
    registerTool(
      Tool(name: _Harness.slowToolName, inputSchema: ObjectSchema()),
      (_) async {
        if (!slowToolCalled.isCompleted) slowToolCalled.complete();
        await finishSlowTool.future;
        if (logAfterTool) log(LoggingLevel.error, 'slow completed');
        if (logAfterTool) {
          unawaited(
            (() async {
              await finishLateLogs.future;
              log(LoggingLevel.error, 'slow completed after response');
            })(),
          );
        }
        if (requestAfterSlowTool) {
          await sendRequest<EmptyResult>(PingRequest.methodName);
        }
        return CallToolResult(content: []);
      },
    );
    registerTool(
      Tool(name: _Harness.otherSlowToolName, inputSchema: ObjectSchema()),
      (_) async {
        if (!otherSlowToolCalled.isCompleted) otherSlowToolCalled.complete();
        await finishOtherSlowTool.future;
        if (logAfterTool) log(LoggingLevel.error, 'other completed');
        if (logAfterTool) {
          unawaited(
            (() async {
              await finishLateLogs.future;
              log(LoggingLevel.error, 'other completed after response');
            })(),
          );
        }
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
    final hold = holdInitialize;
    if (hold != null) await hold.future;
    return super.initialize(initialization);
  }
}

/// A server with open listen requests that expose shutdown response races.
final class _CancellationSubscriptionServer extends MCPServer
    with ResourcesSupport, SubscriptionsSupport {
  _CancellationSubscriptionServer(super.channel)
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'cancellation subscription server',
          version: '1.0.0',
        ),
      );

  int resourceStreamStarts = 0;

  @override
  Duration get resourceUpdateThrottleDelay {
    resourceStreamStarts++;
    return Duration.zero;
  }
}

/// A raw channel around [_CancellationSubscriptionServer].
final class _SubscriptionHarness {
  static final resource = Resource(name: 'watched', uri: 'file:///watched');

  final _toServer = StreamController<Map<String, Object?>>();
  final _fromServer = StreamController<Map<String, Object?>>();
  final frames = <Map<String, Object?>>[];
  late final _CancellationSubscriptionServer server;

  _SubscriptionHarness() {
    _fromServer.stream.listen(frames.add);
    server = _CancellationSubscriptionServer(
      StreamChannel<Map<String, Object?>>.withCloseGuarantee(
        _toServer.stream,
        _fromServer.sink,
      ),
    );
    addTearDown(server.shutdown);
  }

  Iterable<Map<String, Object?>> get acknowledgements => frames.where(
    (frame) =>
        frame['method'] == SubscriptionsAcknowledgedNotification.methodName,
  );

  Iterable<Map<String, Object?>> framesWithId(Object id) =>
      frames.where((frame) => frame['id'] == id);

  Iterable<Map<String, Object?>> get resourceUpdates => frames.where(
    (frame) => frame['method'] == ResourceUpdatedNotification.methodName,
  );

  Future<void> initialize() async {
    server.addResource(resource, (_) => ReadResourceResult(contents: const []));
    await server.initialize(
      MCPServerInitialization(
        protocolVersion: ProtocolVersion.v2026_07_28,
        clientCapabilities: ClientCapabilities(),
      ),
    );
    server.handleInitialized();
  }

  void listen(int id, {SubscriptionFilter? notifications}) {
    server.nextSubscriptionId = RequestId(id);
    _toServer.add({
      'jsonrpc': '2.0',
      'id': id,
      'method': SubscriptionsListenRequest.methodName,
      'params':
          SubscriptionsListenRequest(
                notifications:
                    notifications ?? SubscriptionFilter(toolsListChanged: true),
                meta: MetaWithRequestEnvelope(
                  protocolVersion: ProtocolVersion.v2026_07_28,
                  capabilities: ClientCapabilities(),
                ),
              )
              as Map<String, Object?>,
    });
  }

  void cancel(int id) => _toServer.add({
    'jsonrpc': '2.0',
    'method': CancelledNotification.methodName,
    'params':
        CancelledNotification(requestId: RequestId(id)) as Map<String, Object?>,
  });

  void updateResource() => server.updateResource(resource);
}
