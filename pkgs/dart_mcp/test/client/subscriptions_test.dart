// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/src/shared.dart';
import 'package:dart_mcp/src/utils/constants.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

import '../test_utils.dart';

/// A server on a connection which is not request scoped, the shape a stdio
/// transport for this revision has.
base class _SubscribingServer extends MCPServer
    with ToolsSupport, SubscriptionsSupport {
  _SubscribingServer(super.channel)
    : super.fromStreamChannel(
        implementation: Implementation(name: 'test server', version: '0.1.0'),
      );
}

/// A server whose acknowledgements are missing a field the client reads them
/// by, the shapes the schema leaves room for.
///
/// `notifications` is the only required param on the acknowledgement and
/// `_meta` is not required at all, so a client cannot assume either is there.
/// The subscription is held open until [shutdown] the way
/// [SubscriptionsSupport] holds a well-formed one.
base class _MalformedAckServer extends MCPServer with SubscriptionsSupport {
  _MalformedAckServer(super.channel)
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'malformed ack server',
          version: '0.1.0',
        ),
      );

  /// Ends the subscription this server holds open.
  final _subscriptionEnd = Completer<void>();

  /// Acknowledges the subscription twice, each time leaving out one of the two
  /// fields the client needs, then holds the request open.
  @override
  Future<SubscriptionsListenResult> handleSubscriptionsListen(
    SubscriptionsListenRequest request,
  ) async {
    final subscriptionId = nextSubscriptionId!;
    nextSubscriptionId = null;
    // Carries the filter, but nothing saying which subscription it is for.
    sendNotification(
      SubscriptionsAcknowledgedNotification.methodName,
      SubscriptionsAcknowledgedNotification.fromMap({
        Keys.notifications: SubscriptionFilter(toolsListChanged: true),
      }),
    );
    // Names the subscription, but reports no filter for it.
    sendNotification(
      SubscriptionsAcknowledgedNotification.methodName,
      SubscriptionsAcknowledgedNotification.fromMap({
        Keys.meta: MetaWithSubscriptionId(subscriptionId: subscriptionId),
      }),
    );
    await _subscriptionEnd.future;
    return SubscriptionsListenResult(
      meta: MetaWithSubscriptionId(subscriptionId: subscriptionId),
    );
  }

  /// Ends the held subscription before closing the connection, so its request
  /// still gets the response a server tearing a subscription down sends.
  @override
  Future<void> shutdown() async {
    if (!_subscriptionEnd.isCompleted) {
      _subscriptionEnd.complete();
      // `package:json_rpc_2` writes the response in a microtask once the
      // handler returns, and drops it once the connection is closed.
      await Future<void>.delayed(Duration.zero);
    }
    await super.shutdown();
  }
}

/// Collects the protocol log lines a [TestEnvironment] writes.
class _LogSink implements Sink<String> {
  _LogSink({this.onAdd});

  void Function(String data)? onAdd;
  final lines = <String>[];

  @override
  void add(String data) {
    lines.add(data);
    onAdd?.call(data);
  }

  @override
  void close() {}
}

final class _ControlledCancellationChannel
    extends DelegatingStreamChannel<Map<String, Object?>>
    implements RequestCancellation {
  _ControlledCancellationChannel(super.channel, this.onCancel);

  final void Function(RequestId id) onCancel;

  @override
  Future<void> cancelRequest(RequestId requestId) async => onCancel(requestId);
}

void main() {
  late TestEnvironment<TestMCPClient, _SubscribingServer> environment;
  late _LogSink protocolLog;

  setUp(() async {
    protocolLog = _LogSink();
    environment = TestEnvironment(
      TestMCPClient(),
      _SubscribingServer.new,
      protocolLogSink: protocolLog,
    );
    // The 2026-07-28 revision took the `initialize` handshake out, so a
    // transport for it hands the server its context directly.
    await environment.server.initialize(
      MCPServerInitialization(
        protocolVersion: ProtocolVersion.v2026_07_28,
        clientCapabilities: environment.client.capabilities,
      ),
    );
    environment.server.handleInitialized();
  });

  /// Opens a subscription for [notifications] and names it on the server the
  /// way a transport serving this method does.
  ///
  /// `listen` returns before the request reaches the server, so the ID it went
  /// out under is there to name the subscription by.
  Subscription listen([SubscriptionFilter? notifications]) {
    final subscription = environment.serverConnection.listen(
      notifications ?? SubscriptionFilter(toolsListChanged: true),
      meta: MetaWithRequestEnvelope(
        protocolVersion: ProtocolVersion.v2026_07_28,
        capabilities: environment.client.capabilities,
      ),
    );
    environment.server.nextSubscriptionId = subscription.id;
    return subscription;
  }

  /// Sends a tools-list change from the server under [subscriptionId], the way
  /// a server stamps every message it sends on a subscription.
  void notifyToolsListChanged(RequestId subscriptionId) =>
      environment.server.sendNotification(
        ToolListChangedNotification.methodName,
        ToolListChangedNotification(
          meta: MetaWithSubscriptionId(subscriptionId: subscriptionId),
        ),
      );

  /// The subscription ID on [notification], read off its raw metadata.
  Object? subscriptionIdOf(SubscriptionNotification notification) {
    final meta = (notification.params as Map<String, Object?>)[Keys.meta];
    return (meta as Map<String, Object?>)[Keys.subscriptionIdMeta];
  }

  test(
    'the ID names the JSON-RPC request the subscription went out on',
    () async {
      final subscription = listen();
      await subscription.acknowledged.timeout(const Duration(seconds: 5));

      final sent = protocolLog.lines.singleWhere(
        (line) =>
            line.startsWith('>>>') &&
            line.contains(SubscriptionsListenRequest.methodName),
      );
      expect(
        sent,
        contains('"id":${subscription.id}'),
        reason: 'the handle reports the ID the request was written with',
      );
      final message =
          jsonDecode(sent.substring(sent.indexOf('{'))) as Map<String, Object?>;
      expect((message[Keys.params] as Map<String, Object?>)[Keys.meta], {
        Keys.protocolVersionMeta: '2026-07-28',
        Keys.clientCapabilitiesMeta: <String, Object?>{},
      });
    },
  );

  test('reports the filter the server acknowledged', () async {
    final subscription = listen();
    final acknowledged = await subscription.acknowledged.timeout(
      const Duration(seconds: 5),
    );
    expect(acknowledged.toolsListChanged, isTrue);
    expect(
      acknowledged.resourcesListChanged,
      isNull,
      reason: 'a type the server does not support is left out, not sent false',
    );
  });

  test(
    'records the subscription before a synchronous ack and change',
    () async {
      final controller = StreamChannelController<Map<String, Object?>>(
        sync: true,
      );
      final client = TestMCPClient();
      final connection = client.connectServer(controller.foreign);
      addTearDown(client.shutdown);
      late RequestId requestId;
      controller.local.stream.listen((message) {
        if (message[Keys.method] != SubscriptionsListenRequest.methodName)
          return;
        requestId = RequestId(message[Keys.id]!);
        controller.local.sink
          ..add({
            Keys.jsonrpc: '2.0',
            Keys.method: SubscriptionsAcknowledgedNotification.methodName,
            Keys.params: SubscriptionsAcknowledgedNotification(
              notifications: SubscriptionFilter(toolsListChanged: true),
              meta: MetaWithSubscriptionId(subscriptionId: requestId),
            ),
          })
          ..add({
            Keys.jsonrpc: '2.0',
            Keys.method: ToolListChangedNotification.methodName,
            Keys.params: ToolListChangedNotification(
              meta: MetaWithSubscriptionId(subscriptionId: requestId),
            ),
          })
          ..add({
            Keys.jsonrpc: '2.0',
            Keys.id: requestId,
            Keys.result: SubscriptionsListenResult(
              meta: MetaWithSubscriptionId(subscriptionId: requestId),
            ),
          });
      });

      final subscription = connection.listen(
        SubscriptionFilter(toolsListChanged: true),
        meta: MetaWithRequestEnvelope(
          protocolVersion: ProtocolVersion.v2026_07_28,
          capabilities: client.capabilities,
        ),
      );
      final notification = subscription.notifications.first;

      expect((await subscription.acknowledged).toolsListChanged, isTrue);
      expect(
        (await notification).method,
        ToolListChangedNotification.methodName,
      );
      await subscription.done;
    },
  );

  test('keeps the listen ID when logging sends a nested request', () async {
    var sentPing = false;
    protocolLog.onAdd = (line) {
      if (sentPing ||
          !line.startsWith('>>>') ||
          !line.contains(SubscriptionsListenRequest.methodName)) {
        return;
      }
      sentPing = true;
      unawaited(environment.serverConnection.ping());
    };

    final subscription = listen();
    await subscription.acknowledged.timeout(const Duration(seconds: 5));
    final requests =
        protocolLog.lines
            .where((line) => line.startsWith('>>>') && line.contains('"id"'))
            .map(
              (line) =>
                  jsonDecode(line.substring(line.indexOf('{')))
                      as Map<String, Object?>,
            )
            .toList();
    final listenRequest = requests.singleWhere(
      (request) =>
          request[Keys.method] == SubscriptionsListenRequest.methodName,
    );
    final pingRequest = requests.singleWhere(
      (request) => request[Keys.method] == PingRequest.methodName,
    );

    expect(subscription.id, listenRequest[Keys.id]);
    expect(subscription.id, isNot(pingRequest[Keys.id]));
  });

  test('closes over stdio with one cancellation notification', () async {
    final subscription = listen();
    final listener = subscription.notifications.listen((_) {});
    listener.pause();
    addTearDown(listener.cancel);
    await subscription.acknowledged.timeout(const Duration(seconds: 5));
    final other = listen();
    final otherEvents = <SubscriptionNotification>[];
    final otherListener = other.notifications.listen(otherEvents.add);
    addTearDown(otherListener.cancel);
    await other.acknowledged.timeout(const Duration(seconds: 5));

    await subscription.close().timeout(const Duration(seconds: 5));
    await subscription.done.timeout(const Duration(seconds: 5));
    await subscription.close().timeout(const Duration(seconds: 5));
    notifyToolsListChanged(other.id);
    await pumpEventQueue();
    expect(otherEvents, hasLength(1));
    await expectLater(environment.serverConnection.ping(), completes);

    final cancelled =
        protocolLog.lines
            .where(
              (line) =>
                  line.startsWith('>>>') &&
                  line.contains(CancelledNotification.methodName),
            )
            .map(
              (line) =>
                  jsonDecode(line.substring(line.indexOf('{')))
                      as Map<String, Object?>,
            )
            .toList();
    expect(cancelled, hasLength(1));
    expect(cancelled.single, {
      Keys.jsonrpc: '2.0',
      Keys.method: CancelledNotification.methodName,
      Keys.params: {Keys.requestId: subscription.id},
    });
    await other.close().timeout(const Duration(seconds: 5));
  });

  test('local completion wins a cancellation transport error', () async {
    final controller = StreamChannelController<Map<String, Object?>>(
      sync: true,
    );
    late RequestId requestId;
    controller.local.stream.listen((message) {
      if (message[Keys.method] != SubscriptionsListenRequest.methodName) return;
      requestId = RequestId(message[Keys.id]!);
      controller.local.sink.add({
        Keys.jsonrpc: '2.0',
        Keys.method: SubscriptionsAcknowledgedNotification.methodName,
        Keys.params: SubscriptionsAcknowledgedNotification(
          notifications: SubscriptionFilter(toolsListChanged: true),
          meta: MetaWithSubscriptionId(subscriptionId: requestId),
        ),
      });
    });
    final channel = _ControlledCancellationChannel(
      controller.foreign,
      (id) => controller.local.sink.add({
        Keys.jsonrpc: '2.0',
        Keys.id: id,
        Keys.error: {Keys.code: -32000, Keys.message: 'cancelled transport'},
      }),
    );
    final client = TestMCPClient();
    final connection = client.connectServer(channel);
    addTearDown(client.shutdown);
    final subscription = connection.listen(
      SubscriptionFilter(toolsListChanged: true),
      meta: MetaWithRequestEnvelope(
        protocolVersion: ProtocolVersion.v2026_07_28,
        capabilities: client.capabilities,
      ),
    );
    await subscription.acknowledged;

    await expectLater(subscription.close(), completes);
    await expectLater(subscription.done, completes);
  });

  test(
    'delivers only the notifications carrying this subscription ID',
    () async {
      final first = listen();
      final firstEvents = <SubscriptionNotification>[];
      final firstListener = first.notifications.listen(firstEvents.add);
      addTearDown(firstListener.cancel);
      await first.acknowledged.timeout(const Duration(seconds: 5));

      final second = listen();
      final secondEvents = <SubscriptionNotification>[];
      final secondListener = second.notifications.listen(secondEvents.add);
      addTearDown(secondListener.cancel);
      await second.acknowledged.timeout(const Duration(seconds: 5));

      expect(
        second.id,
        isNot(first.id),
        reason: 'two subscriptions on one connection get two request IDs',
      );

      notifyToolsListChanged(second.id);
      await pumpEventQueue();

      expect(
        firstEvents,
        isEmpty,
        reason: 'a notification named by another subscription is not ours',
      );
      expect(secondEvents, hasLength(1));
      expect(subscriptionIdOf(secondEvents.single), second.id);

      notifyToolsListChanged(first.id);
      await pumpEventQueue();

      expect(firstEvents, hasLength(1));
      expect(subscriptionIdOf(firstEvents.single), first.id);
      expect(
        secondEvents,
        hasLength(1),
        reason: 'the second subscription got nothing more',
      );
    },
  );

  test('preserves each list change method', () async {
    final subscription = listen(
      SubscriptionFilter(
        toolsListChanged: true,
        promptsListChanged: true,
        resourcesListChanged: true,
      ),
    );
    final events = <SubscriptionNotification>[];
    final listener = subscription.notifications.listen(events.add);
    addTearDown(listener.cancel);
    await subscription.acknowledged.timeout(const Duration(seconds: 5));
    final meta = MetaWithSubscriptionId(subscriptionId: subscription.id);

    environment.server
      ..sendNotification(
        ToolListChangedNotification.methodName,
        ToolListChangedNotification(meta: meta),
      )
      ..sendNotification(
        PromptListChangedNotification.methodName,
        PromptListChangedNotification(meta: meta),
      )
      ..sendNotification(
        ResourceListChangedNotification.methodName,
        ResourceListChangedNotification(meta: meta),
      );
    await pumpEventQueue();

    expect(events.map((event) => event.method), [
      ToolListChangedNotification.methodName,
      PromptListChangedNotification.methodName,
      ResourceListChangedNotification.methodName,
    ]);
    expect(events.map(subscriptionIdOf), everyElement(subscription.id));
  });

  test('drops a notification which carries no subscription ID', () async {
    final subscription = listen();
    final events = <SubscriptionNotification>[];
    final listener = subscription.notifications.listen(events.add);
    addTearDown(listener.cancel);
    await subscription.acknowledged.timeout(const Duration(seconds: 5));

    environment.server.sendNotification(
      ToolListChangedNotification.methodName,
      ToolListChangedNotification(),
    );
    await pumpEventQueue();

    expect(
      events,
      isEmpty,
      reason: 'an unnamed notification belongs to no subscription',
    );
  });

  test(
    'completes with the result the server ends the subscription with',
    () async {
      final subscription = listen();
      var closed = false;
      final listener = subscription.notifications.listen(
        (_) {},
        onDone: () => closed = true,
      );
      listener.pause();
      addTearDown(listener.cancel);
      await subscription.acknowledged.timeout(const Duration(seconds: 5));

      var completed = false;
      unawaited(subscription.done.then((_) => completed = true));
      await pumpEventQueue();
      expect(
        completed,
        isFalse,
        reason: 'the subscription stays open until the server ends it',
      );

      unawaited(environment.server.shutdown());
      await subscription.done.timeout(const Duration(seconds: 5));
      expect(
        closed,
        isFalse,
        reason: 'a paused listener does not hold the subscription result',
      );
      listener.resume();
      await pumpEventQueue();
      expect(closed, isTrue, reason: 'the stream closes with the subscription');
      await subscription.close().timeout(const Duration(seconds: 5));
      expect(
        protocolLog.lines.where(
          (line) => line.contains(CancelledNotification.methodName),
        ),
        isEmpty,
        reason: 'closing a subscription the server ended sends nothing',
      );
    },
  );

  test('leaves a subscription unacknowledged on a malformed ack', () async {
    final malformed = TestEnvironment(TestMCPClient(), _MalformedAckServer.new);
    await malformed.server.initialize(
      MCPServerInitialization(
        protocolVersion: ProtocolVersion.v2026_07_28,
        clientCapabilities: malformed.client.capabilities,
      ),
    );
    malformed.server.handleInitialized();

    final subscription = malformed.serverConnection.listen(
      SubscriptionFilter(toolsListChanged: true),
      meta: MetaWithRequestEnvelope(
        protocolVersion: ProtocolVersion.v2026_07_28,
        capabilities: malformed.client.capabilities,
      ),
    );
    malformed.server.nextSubscriptionId = subscription.id;
    await pumpEventQueue();

    await expectLater(
      subscription.acknowledged.timeout(Duration.zero),
      throwsA(isA<TimeoutException>()),
      reason: 'an acknowledgement missing a field reports no filter',
    );

    unawaited(malformed.server.shutdown());
    await subscription.done.timeout(const Duration(seconds: 5));
    await expectLater(
      subscription.acknowledged,
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Closed before acknowledgement.',
        ),
      ),
    );
  });

  test('reports a refused subscription on both of its ends', () async {
    // A transport which does not name the subscription gets the request
    // refused, and neither end of the handle may hang on that.
    final subscription = environment.serverConnection.listen(
      SubscriptionFilter(toolsListChanged: true),
      meta: MetaWithRequestEnvelope(
        protocolVersion: ProtocolVersion.v2026_07_28,
        capabilities: environment.client.capabilities,
      ),
    );
    final streamError = Completer<Object>();
    final streamDone = Completer<void>();
    final listener = subscription.notifications.listen(
      (_) {},
      onError: (Object error) => streamError.complete(error),
      onDone: streamDone.complete,
    );
    listener.pause();
    addTearDown(listener.cancel);
    await expectLater(
      subscription.done.timeout(const Duration(seconds: 5)),
      throwsA(isA<RpcException>()),
    );
    await expectLater(
      subscription.acknowledged.timeout(const Duration(seconds: 5)),
      throwsA(isA<RpcException>()),
    );
    expect(streamError.isCompleted, isFalse);
    listener.resume();
    expect(await streamError.future, isA<RpcException>());
    await streamDone.future;
  });
}
