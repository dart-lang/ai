// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/src/utils/constants.dart';
import 'package:json_rpc_2/error_code.dart' as error_code;
import 'package:test/test.dart';

import '../test_utils.dart';

void main() {
  group('request dispatcher', () {
    test('serves a request on a fresh initialized server', () async {
      final harness = _DispatcherHarness();
      final response = await harness.dispatch(
        _callTool('probe'),
        _initialization(),
      );

      expect(harness.servers, hasLength(1));
      final result = _result(response);
      final toolResult = CallToolResult.fromMap(result);
      expect(
        (toolResult.content.single as TextContent).text,
        'ready: true',
        reason: 'initialized must complete before the message is handled',
      );
    });

    test('records server info on the response', () async {
      final harness = _DispatcherHarness();
      final response = await harness.dispatch(
        _callTool('probe'),
        _initialization(),
      );

      final meta = _result(response)[Keys.meta] as Map<String, Object?>;
      final serverInfo = Implementation.fromMap(
        meta[Keys.serverInfoMeta] as Map<String, Object?>,
      );
      expect(serverInfo.name, 'test server');
      expect(serverInfo.version, '0.1.0');
    });

    test('preserves an existing server info entry', () async {
      final harness = _DispatcherHarness();
      final response = await harness.dispatch(
        _callTool('custom_info'),
        _initialization(),
      );

      final meta = _result(response)[Keys.meta] as Map<String, Object?>;
      final serverInfo = Implementation.fromMap(
        meta[Keys.serverInfoMeta] as Map<String, Object?>,
      );
      expect(serverInfo.name, 'already there');
    });

    test('records a result type on the response', () async {
      final harness = _DispatcherHarness();
      final response = await harness.dispatch(
        _callTool('probe'),
        _initialization(),
      );

      expect(_result(response), containsPair(Keys.resultType, 'complete'));
    });

    test('preserves the result type a handler chose', () async {
      final harness = _DispatcherHarness();
      final response = await harness.dispatch(
        _callTool('interim'),
        _initialization(),
      );

      expect(
        _result(response),
        containsPair(Keys.resultType, 'input_required'),
      );
    });

    test('records caching hints on a result which takes them', () async {
      final harness = _DispatcherHarness();
      final response = await harness.dispatch(_listTools(), _initialization());

      expect(_result(response), containsPair(Keys.ttlMs, 0));
      expect(_result(response), containsPair(Keys.cacheScope, 'private'));
    });

    test('leaves caching hints off results which do not take them', () async {
      final harness = _DispatcherHarness();
      final response = await harness.dispatch(
        _callTool('probe'),
        _initialization(),
      );

      expect(_result(response), isNot(contains(Keys.ttlMs)));
      expect(_result(response), isNot(contains(Keys.cacheScope)));
    });

    test('records caching hints on a read as well as a list', () async {
      final harness = _DispatcherHarness();
      final response = await harness.dispatch(
        _readResource(),
        _initialization(),
      );

      expect(_result(response), containsPair(Keys.ttlMs, 0));
      expect(_result(response), containsPair(Keys.cacheScope, 'private'));
    });

    test('preserves the caching hints a handler chose', () async {
      final response = await _dispatchShapedList(
        (result) => {...result, Keys.ttlMs: 5000, Keys.cacheScope: 'public'},
      );

      expect(_result(response), containsPair(Keys.ttlMs, 5000));
      expect(_result(response), containsPair(Keys.cacheScope, 'public'));
    });

    test('sends none of these fields on an earlier revision', () async {
      // All of them are 2026-07-28 vocabulary, including the reserved
      // metadata key.
      final harness = _DispatcherHarness();
      final response = await harness.dispatch(
        _listTools(),
        _initialization(protocolVersion: ProtocolVersion.v2025_11_25),
      );

      expect(_result(response), isNot(contains(Keys.resultType)));
      expect(_result(response), isNot(contains(Keys.ttlMs)));
      expect(_result(response), isNot(contains(Keys.cacheScope)));
      expect(_result(response), isNot(contains(Keys.meta)));
    });

    test('fills in fields a handler left null', () async {
      // A null is a field the handler did not answer, not an answer of null:
      // sending one on the wire would be a value the schema does not allow.
      final response = await _dispatchShapedList(
        (result) => {
          ...result,
          Keys.resultType: null,
          Keys.ttlMs: null,
          Keys.cacheScope: null,
        },
      );

      expect(
        _result(response),
        containsPair(Keys.resultType, ResultTypes.complete),
      );
      expect(_result(response), containsPair(Keys.ttlMs, 0));
      expect(_result(response), containsPair(Keys.cacheScope, 'private'));
    });

    test('fills in the caching hint a handler left out', () async {
      final withTtl = await _dispatchShapedList(
        (result) => {...result, Keys.ttlMs: 5000},
      );
      expect(_result(withTtl), containsPair(Keys.ttlMs, 5000));
      expect(_result(withTtl), containsPair(Keys.cacheScope, 'private'));

      final withScope = await _dispatchShapedList(
        (result) => {...result, Keys.cacheScope: 'public'},
      );
      expect(_result(withScope), containsPair(Keys.ttlMs, 0));
      expect(_result(withScope), containsPair(Keys.cacheScope, 'public'));
    });

    test('replaces a caching hint the schema does not allow', () async {
      final response = await _dispatchShapedList(
        (result) => {...result, Keys.ttlMs: -1, Keys.cacheScope: 'shared'},
      );

      expect(_result(response), containsPair(Keys.ttlMs, 0));
      expect(_result(response), containsPair(Keys.cacheScope, 'private'));
    });

    test('records caching hints despite a result type the schema does not '
        'give the request', () async {
      // `tools/list` has no interim arm, so a non-complete type there does not
      // make the result one the caching rules exempt.
      final response = await _dispatchShapedList(
        (result) => {...result, Keys.resultType: 'input_required'},
      );

      expect(_result(response), containsPair(Keys.ttlMs, 0));
      expect(_result(response), containsPair(Keys.cacheScope, 'private'));
    });

    test('leaves caching hints off an interim result', () async {
      // The schema gives `resources/read` an interim arm; `tools/list` has
      // none, so a list result is never the one waiting on input.
      final response = await _dispatchShapedRead(
        (result) => {...result, Keys.resultType: 'input_required'},
      );

      expect(_result(response), isNot(contains(Keys.ttlMs)));
      expect(_result(response), isNot(contains(Keys.cacheScope)));
    });

    test('answers even when a result has malformed metadata', () async {
      final harness = _DispatcherHarness();
      final response = await harness.dispatch(
        _callTool('bad_meta'),
        _initialization(),
      );

      // Server info stamping is skipped rather than throwing and wedging.
      expect(_result(response)[Keys.meta], 'not a map');
    });

    test('answers even when metadata has non-string keys', () async {
      final harness = _DispatcherHarness();
      final response = await harness.dispatch(
        _callTool('bad_meta_keys'),
        _initialization(),
      );

      // Server info stamping is skipped rather than throwing and wedging.
      expect(_result(response)[Keys.meta], {1: 'kept'});
    });

    test('stamps server info on an unmodifiable result', () async {
      final harness = _DispatcherHarness();
      // The built-in ping handler returns `EmptyResult()`, which is backed
      // by a const map.
      final response = await harness.dispatch(_ping(), _initialization());

      final meta = _result(response)[Keys.meta] as Map<String, Object?>;
      expect(meta[Keys.serverInfoMeta], isNotNull);
    });

    test('leaves the result map a handler returned unmodified', () async {
      final harness = _DispatcherHarness();
      final response = await harness.dispatch(
        _callTool('retained'),
        _initialization(),
      );

      expect(_result(response)[Keys.meta], isNotNull);
      final retained = harness.servers.single.retainedResult!;
      expect(retained, isNot(contains(Keys.meta)));
    });

    test('declares client capabilities per request', () async {
      final harness = _DispatcherHarness();
      await harness.dispatch(
        _callTool('probe'),
        _initialization(
          capabilities: ClientCapabilities(roots: RootsCapabilities()),
        ),
      );
      await harness.dispatch(_callTool('probe'), _initialization());

      expect(harness.servers, hasLength(2));
      final first = harness.servers[0];
      final second = harness.servers[1];
      expect(first, isNot(same(second)));
      expect(first.clientCapabilities.roots, isNotNull);
      expect(second.clientCapabilities.roots, isNull);
    });

    test('serves a request which declares no client info', () async {
      final harness = _DispatcherHarness();
      final response = await harness.dispatch(
        _callTool('probe'),
        _initialization(),
      );

      expect(harness.servers.single.clientInfo, isNull);
      expect(_result(response), isNotEmpty);
    });

    test('passes emitted notifications to onNotification', () async {
      final harness = _DispatcherHarness();
      final notifications = <Map<String, Object?>>[];
      await harness.dispatch(
        _callTool('notify'),
        _initialization(),
        onNotification: notifications.add,
      );

      final methods = [for (final n in notifications) n[Keys.method]];
      expect(methods, contains(ProgressNotification.methodName));
      expect(methods, contains(LoggingMessageNotification.methodName));
    });

    test('delivers notifications emitted during initialization', () async {
      final servers = <_RootsTrackingDispatcherServer>[];
      final notifications = <Map<String, Object?>>[];
      // Without the roots capability, roots tracking logs a warning as it
      // initializes, before the dispatched message is handled.
      await handleRequestScopedMessage(_listTools(), _initialization(), (
        channel,
      ) {
        final server = _RootsTrackingDispatcherServer(channel);
        servers.add(server);
        return server;
      }, onNotification: notifications.add);

      expect(
        notifications.map((n) => n[Keys.method]),
        contains(LoggingMessageNotification.methodName),
      );
    });

    test('fails server to client requests instead of hanging', () async {
      final harness = _DispatcherHarness();
      final response = await harness.dispatch(
        _callTool('roots'),
        _initialization(),
      );

      final error = response![Keys.error] as Map<String, Object?>;
      expect(error[Keys.code], error_code.INTERNAL_ERROR);
      expect(error[Keys.message], contains('request-scoped transport'));
    });

    test('shuts the server down after a dispatch', () async {
      final harness = _DispatcherHarness();
      await harness.dispatch(_callTool('probe'), _initialization());

      final server = harness.servers.single;
      await server.done;
      expect(server.isActive, isFalse);
    });

    test('returns an internal error when the server closes early', () async {
      final harness = _DispatcherHarness();
      final response = await harness.dispatch(
        _callTool('shutdown'),
        _initialization(),
      );

      final error = response![Keys.error] as Map<String, Object?>;
      expect(error[Keys.code], error_code.INTERNAL_ERROR);
      expect(error[Keys.message], contains('closed before responding'));
    });

    test('surfaces initialization failures without unhandled errors', () async {
      final servers = <_FailingInitServer>[];
      await expectLater(
        handleRequestScopedMessage(_callTool('probe'), _initialization(), (
          channel,
        ) {
          final server = _FailingInitServer(channel);
          servers.add(server);
          return server;
        }),
        throwsStateError,
      );
      await servers.single.done;
    });

    test('responds with method not found for unknown methods', () async {
      final harness = _DispatcherHarness();
      final response = await harness.dispatch({
        Keys.jsonrpc: '2.0',
        Keys.id: 1,
        Keys.method: 'no/such_method',
      }, _initialization());

      final error = response![Keys.error] as Map<String, Object?>;
      expect(error[Keys.code], error_code.METHOD_NOT_FOUND);
      expect(
        response.containsKey(Keys.result),
        isFalse,
        reason: 'error responses get no result and no server info',
      );
    });

    test('throws for messages without a string method', () async {
      final harness = _DispatcherHarness();
      await expectLater(
        harness.dispatch({Keys.jsonrpc: '2.0', Keys.id: 1}, _initialization()),
        throwsArgumentError,
      );
      await expectLater(
        harness.dispatch({
          Keys.jsonrpc: '2.0',
          Keys.id: 1,
          Keys.method: 42,
        }, _initialization()),
        throwsArgumentError,
      );
      expect(harness.servers, isEmpty);
    });

    test('throws for response-shaped messages', () async {
      final harness = _DispatcherHarness();
      await expectLater(
        harness.dispatch({
          Keys.jsonrpc: '2.0',
          Keys.id: 1,
          Keys.method: ListToolsRequest.methodName,
          Keys.result: <String, Object?>{},
        }, _initialization()),
        throwsArgumentError,
      );
      await expectLater(
        harness.dispatch({
          Keys.jsonrpc: '2.0',
          Keys.id: 1,
          Keys.method: ListToolsRequest.methodName,
          Keys.error: <String, Object?>{Keys.code: 0, Keys.message: 'x'},
        }, _initialization()),
        throwsArgumentError,
      );
      expect(harness.servers, isEmpty);
    });

    test('throws for legacy lifecycle messages', () async {
      final harness = _DispatcherHarness();
      await expectLater(
        harness.dispatch({
          Keys.jsonrpc: '2.0',
          Keys.id: 1,
          Keys.method: InitializeRequest.methodName,
        }, _initialization()),
        throwsArgumentError,
      );
      await expectLater(
        harness.dispatch({
          Keys.jsonrpc: '2.0',
          Keys.method: InitializedNotification.methodName,
        }, _initialization()),
        throwsArgumentError,
      );
      expect(harness.servers, isEmpty);
    });

    test('returns null for notifications', () async {
      final harness = _DispatcherHarness();
      final response = await harness.dispatch({
        Keys.jsonrpc: '2.0',
        Keys.method: _DispatcherTestServer.testNotification,
      }, _initialization());

      expect(response, isNull);
      expect(harness.servers.single.testNotifications, 1);
    });

    test('throws for a message with a null id', () async {
      final harness = _DispatcherHarness();
      await expectLater(
        harness.dispatch({
          Keys.jsonrpc: '2.0',
          Keys.id: null,
          Keys.method: ListToolsRequest.methodName,
        }, _initialization()),
        throwsArgumentError,
      );
      expect(harness.servers, isEmpty);
    });

    test(
      'reports a throwing onNotification without failing the request',
      () async {
        final harness = _DispatcherHarness();
        final callbackErrors = <Object>[];
        Map<String, Object?>? response;
        await runZonedGuarded(() async {
          response = await harness.dispatch(
            _callTool('notify'),
            _initialization(),
            onNotification: (_) => throw StateError('bad callback'),
          );
        }, (error, _) => callbackErrors.add(error));

        expect(_result(response), isNotEmpty);
        expect(callbackErrors, isNotEmpty);
      },
    );

    test('isolates concurrent dispatches', () async {
      final harness = _DispatcherHarness();
      final responses = await Future.wait([
        harness.dispatch(
          _callTool('slow_echo', arguments: {'message': 'first'}),
          _initialization(
            capabilities: ClientCapabilities(roots: RootsCapabilities()),
          ),
        ),
        harness.dispatch(
          _callTool('slow_echo', arguments: {'message': 'second'}),
          _initialization(),
        ),
      ]);

      final texts = [
        for (final response in responses)
          (CallToolResult.fromMap(_result(response)).content.single
                  as TextContent)
              .text,
      ];
      expect(texts, ['first', 'second']);
      expect(harness.servers, hasLength(2));
      expect(harness.servers[0].clientCapabilities.roots, isNotNull);
      expect(harness.servers[1].clientCapabilities.roots, isNull);
    });

    test('degrades gracefully with roots tracking mixed in', () async {
      final servers = <_RootsTrackingDispatcherServer>[];
      final response = await handleRequestScopedMessage(
        _listTools(),
        _initialization(
          capabilities: ClientCapabilities(roots: RootsCapabilities()),
        ),
        (channel) {
          final server = _RootsTrackingDispatcherServer(channel);
          servers.add(server);
          return server;
        },
      );

      final tools = ListToolsResult.fromMap(_result(response));
      expect(tools.tools, isEmpty);
      await servers.single.done;
    });

    test(
      'survives a notification which triggers a server to client request',
      () async {
        // The immediate teardown after a notification races the listRoots
        // request that roots tracking issues on initialization.
        final response = await handleRequestScopedMessage(
          {
            Keys.jsonrpc: '2.0',
            Keys.method: _DispatcherTestServer.testNotification,
          },
          _initialization(
            capabilities: ClientCapabilities(roots: RootsCapabilities()),
          ),
          _RootsTrackingDispatcherServer.new,
        );

        expect(response, isNull);
      },
    );
  });

  group('legacy lifecycle', () {
    test('handshake still provides client info', () async {
      final environment = TestEnvironment(
        TestMCPClient(),
        _DispatcherTestServer.new,
      );
      await environment.initializeServer();

      expect(
        environment.server.clientInfo?.name,
        environment.client.implementation.name,
      );
    });
  });
}

/// Dispatches messages over [_DispatcherTestServer]s and records the servers
/// it creates.
final class _DispatcherHarness {
  final servers = <_DispatcherTestServer>[];

  Future<Map<String, Object?>?> dispatch(
    Map<String, Object?> message,
    MCPServerInitialization initialization, {
    void Function(Map<String, Object?> notification)? onNotification,
  }) => handleRequestScopedMessage(message, initialization, (channel) {
    final server = _DispatcherTestServer(channel);
    servers.add(server);
    return server;
  }, onNotification: onNotification);
}

/// A server with tools which observe the request-scoped lifecycle.
final class _DispatcherTestServer extends TestMCPServer
    with LoggingSupport, ResourcesSupport, ToolsSupport {
  static const testNotification = 'notifications/test';

  _DispatcherTestServer(super.channel);

  /// How many [testNotification] notifications this server received.
  int testNotifications = 0;

  /// The result map the `retained` tool returned, to assert that server info
  /// stamping does not write into it.
  Map<String, Object?>? retainedResult;

  @override
  FutureOr<ServerCapabilities> initialize(
    MCPServerInitialization initialization,
  ) {
    registerNotificationHandler(testNotification, (Notification? _) {
      testNotifications++;
    });
    registerTool(
      Tool(name: 'probe', inputSchema: ObjectSchema()),
      (_) => CallToolResult(content: [TextContent(text: 'ready: $ready')]),
    );
    registerTool(
      Tool(name: 'custom_info', inputSchema: ObjectSchema()),
      (_) => CallToolResult.fromMap({
        Keys.content: [TextContent(text: 'custom')],
        Keys.meta: {
          Keys.serverInfoMeta: Implementation(
            name: 'already there',
            version: '1.0.0',
          ),
        },
      }),
    );
    addResource(
      Resource(uri: 'file:///probe', name: 'probe'),
      (_) async => ReadResourceResult(
        contents: [TextResourceContents(uri: 'file:///probe', text: 'probe')],
      ),
    );
    registerTool(
      Tool(name: 'interim', inputSchema: ObjectSchema()),
      (_) => CallToolResult.fromMap({
        Keys.content: [TextContent(text: 'waiting')],
        Keys.resultType: 'input_required',
      }),
    );
    registerTool(
      Tool(name: 'bad_meta', inputSchema: ObjectSchema()),
      (_) => CallToolResult.fromMap({
        Keys.content: [TextContent(text: 'bad')],
        Keys.meta: 'not a map',
      }),
    );
    registerTool(
      Tool(name: 'bad_meta_keys', inputSchema: ObjectSchema()),
      (_) => CallToolResult.fromMap({
        Keys.content: [TextContent(text: 'bad')],
        Keys.meta: {1: 'kept'},
      }),
    );
    registerTool(Tool(name: 'retained', inputSchema: ObjectSchema()), (_) {
      retainedResult = {
        Keys.content: [TextContent(text: 'kept')],
      };
      return CallToolResult.fromMap(retainedResult!);
    });
    registerTool(Tool(name: 'notify', inputSchema: ObjectSchema()), (_) {
      notifyProgress(
        ProgressNotification(progressToken: ProgressToken(1), progress: 50),
      );
      log(LoggingLevel.error, 'from the handler');
      return CallToolResult(content: [TextContent(text: 'notified')]);
    });
    registerTool(Tool(name: 'roots', inputSchema: ObjectSchema()), (_) async {
      final roots = await listRoots(ListRootsRequest());
      return CallToolResult(content: [TextContent(text: '$roots')]);
    });
    registerTool(Tool(name: 'shutdown', inputSchema: ObjectSchema()), (
      _,
    ) async {
      await shutdown();
      return CallToolResult(content: [TextContent(text: 'unreachable')]);
    });
    registerTool(Tool(name: 'slow_echo', inputSchema: ObjectSchema()), (
      request,
    ) async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return CallToolResult(
        content: [TextContent(text: request.arguments!['message'] as String)],
      );
    });
    return super.initialize(initialization);
  }
}

/// A server which tracks roots, to exercise a server to client request made
/// during initialization rather than from a handler.
final class _RootsTrackingDispatcherServer extends TestMCPServer
    with LoggingSupport, RootsTrackingSupport, ToolsSupport {
  _RootsTrackingDispatcherServer(super.channel);
}

/// A server whose initialization always fails.
final class _FailingInitServer extends TestMCPServer {
  _FailingInitServer(super.channel);

  @override
  // A server which fails to initialize cannot call super first.
  // ignore: must_call_super
  FutureOr<ServerCapabilities> initialize(
    MCPServerInitialization initialization,
  ) => throw StateError('initialization failed');
}

/// A server whose `resources/read` answers with whatever [shape] returns.
final class _ShapedReadServer extends TestMCPServer with ResourcesSupport {
  _ShapedReadServer(super.channel, this.shape);

  final Map<String, Object?> Function(Map<String, Object?> result) shape;

  @override
  FutureOr<ServerCapabilities> initialize(
    MCPServerInitialization initialization,
  ) {
    addResource(
      Resource(uri: 'file:///probe', name: 'probe'),
      (_) async => ReadResourceResult(contents: []),
    );
    return super.initialize(initialization);
  }

  @override
  Future<ReadResourceResult> readResource(ReadResourceRequest request) async =>
      ReadResourceResult.fromMap(
        shape(await super.readResource(request) as Map<String, Object?>),
      );
}

/// A server whose `tools/list` answers with whatever [shape] returns.
final class _ShapedListServer extends TestMCPServer with ToolsSupport {
  _ShapedListServer(super.channel, this.shape);

  final Map<String, Object?> Function(Map<String, Object?> result) shape;

  @override
  Future<ListToolsResult> listTools([ListToolsRequest? request]) async =>
      ListToolsResult.fromMap(
        shape(await super.listTools(request) as Map<String, Object?>),
      );
}

Map<String, Object?> _callTool(
  String name, {
  Map<String, Object?> arguments = const {},
}) => {
  Keys.jsonrpc: '2.0',
  Keys.id: 1,
  Keys.method: CallToolRequest.methodName,
  Keys.params: {Keys.name: name, Keys.arguments: arguments},
};

Map<String, Object?> _readResource() => {
  Keys.jsonrpc: '2.0',
  Keys.id: 1,
  Keys.method: ReadResourceRequest.methodName,
  Keys.params: {Keys.uri: 'file:///probe'},
};

Map<String, Object?> _listTools() => {
  Keys.jsonrpc: '2.0',
  Keys.id: 1,
  Keys.method: ListToolsRequest.methodName,
};

Map<String, Object?> _ping() => {
  Keys.jsonrpc: '2.0',
  Keys.id: 1,
  Keys.method: PingRequest.methodName,
};

/// The request-scoped lifecycle arrived with 2026-07-28, so that is the
/// revision these dispatch, unless a test says otherwise.
MCPServerInitialization _initialization({
  ClientCapabilities? capabilities,
  ProtocolVersion protocolVersion = ProtocolVersion.v2026_07_28,
}) => MCPServerInitialization(
  protocolVersion: protocolVersion,
  clientCapabilities: capabilities ?? ClientCapabilities(),
);

Map<String, Object?> _result(Map<String, Object?>? response) =>
    response![Keys.result] as Map<String, Object?>;

/// Dispatches a `resources/read` to a server whose result is passed through
/// [shape] first, so a test can say what the handler itself already set.
Future<Map<String, Object?>?> _dispatchShapedRead(
  Map<String, Object?> Function(Map<String, Object?> result) shape,
) => handleRequestScopedMessage(
  _readResource(),
  _initialization(),
  (channel) => _ShapedReadServer(channel, shape),
);

/// Dispatches a `tools/list` to a server whose result is passed through
/// [shape] first, so a test can say what the handler itself already set.
Future<Map<String, Object?>?> _dispatchShapedList(
  Map<String, Object?> Function(Map<String, Object?> result) shape,
) => handleRequestScopedMessage(
  _listTools(),
  _initialization(),
  (channel) => _ShapedListServer(channel, shape),
);
