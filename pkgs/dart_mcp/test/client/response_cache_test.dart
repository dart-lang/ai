// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/src/utils/constants.dart';
import 'package:json_rpc_2/error_code.dart' as error_code;
import 'package:json_rpc_2/json_rpc_2.dart' show RpcException;
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

import '../test_utils.dart';

void main() {
  test('client does not cache modern-shaped legacy responses', () async {
    late _CacheServer server;
    final environment = TestEnvironment(
      TestMCPClient(),
      (channel) => server = _CacheServer(channel),
    );

    await environment.serverConnection.listTools();
    await environment.serverConnection.listTools();

    expect(server.calls[ListToolsRequest.methodName], 2);
  });

  test('client caches inline responses without a resultType', () async {
    late _CacheServer server;
    final environment = TestEnvironment(
      TestMCPClient(),
      (channel) => server = _CacheServer(channel),
    );
    server.includeResultType = false;
    ListToolsRequest request(String extension) => ListToolsRequest(
      meta: MetaWithProgressToken.fromMap({
        Keys.protocolVersionMeta: ProtocolVersion.v2026_07_28.versionString,
        Keys.clientCapabilitiesMeta: {
          Keys.extensions: {extension: <String, Object?>{}},
        },
      }),
    );

    await environment.serverConnection.listTools(request('com.example/one'));
    await environment.serverConnection.listTools(request('com.example/one'));
    expect(server.calls[ListToolsRequest.methodName], 1);
  });

  test('client caches request-scoped server responses', () async {
    final responses = StreamController<Map<String, Object?>>();
    final requests = StreamController<Map<String, Object?>>();
    final calls = <String, int>{};
    final subscription = requests.stream
        .asyncMap((message) {
          return handleRequestScopedMessage(
            message,
            MCPServerInitialization(
              protocolVersion: ProtocolVersion.v2026_07_28,
              clientCapabilities: ClientCapabilities(),
            ),
            (channel) => _RequestScopedCacheServer(channel, calls),
          );
        })
        .listen((response) {
          if (response != null) responses.add(response);
        });
    final client = TestMCPClient();
    final connection = client.connectServer(
      StreamChannel.withCloseGuarantee(responses.stream, requests.sink),
    );
    addTearDown(() async {
      await client.shutdown();
      await subscription.cancel();
      if (!responses.isClosed) await responses.close();
    });
    final meta = MetaWithProgressToken.fromMap({
      Keys.protocolVersionMeta: ProtocolVersion.v2026_07_28.versionString,
      Keys.clientCapabilitiesMeta: <String, Object?>{},
    });

    await connection.listTools(ListToolsRequest(meta: meta));
    await connection.listTools(ListToolsRequest(meta: meta));
    expect(calls[ListToolsRequest.methodName], 1);

    await connection.listTools();
    await connection.listTools();
    expect(calls[ListToolsRequest.methodName], 3);
  });

  group('client response cache', () {
    late TestEnvironment<TestMCPClient, _CacheServer> environment;
    late _CacheServer server;
    late ServerConnection connection;

    /// The envelope the schema requires on a 2026-07-28 request, and what
    /// selects the cache.
    final meta = MetaWithProgressToken.fromMap({
      Keys.protocolVersionMeta: ProtocolVersion.v2026_07_28.versionString,
    });

    setUp(() async {
      environment = TestEnvironment(
        TestMCPClient(),
        (channel) => server = _CacheServer(channel),
      );
      connection = environment.serverConnection;
    });

    Future<DiscoverResult> discover() => connection.discover(
      protocolVersion: ProtocolVersion.v2026_07_28,
      capabilities: ClientCapabilities(),
    );
    Future<ListToolsResult> listTools([Cursor? cursor]) =>
        connection.listTools(ListToolsRequest(cursor: cursor, meta: meta));
    Future<ListPromptsResult> listPrompts() =>
        connection.listPrompts(ListPromptsRequest(meta: meta));
    Future<ListResourcesResult> listResources() =>
        connection.listResources(ListResourcesRequest(meta: meta));
    Future<ListResourceTemplatesResult> listResourceTemplates() => connection
        .listResourceTemplates(ListResourceTemplatesRequest(meta: meta));
    Future<ReadResourceResult> readResource(String uri) =>
        connection.readResource(ReadResourceRequest(uri: uri, meta: meta));

    test('separates modern request contexts', () async {
      ListToolsRequest request(String extension) => ListToolsRequest(
        meta: MetaWithProgressToken.fromMap({
          Keys.protocolVersionMeta: ProtocolVersion.v2026_07_28.versionString,
          Keys.clientCapabilitiesMeta: {
            Keys.extensions: {extension: <String, Object?>{}},
          },
        }),
      );

      await connection.listTools(request('com.example/one'));
      await connection.listTools(request('com.example/one'));
      expect(server.calls[ListToolsRequest.methodName], 1);

      await connection.listTools(request('com.example/two'));
      expect(server.calls[ListToolsRequest.methodName], 2);
    });

    test('caches the six cacheable operations', () async {
      await discover();
      await discover();
      await listTools();
      await listTools();
      await listPrompts();
      await listPrompts();
      await listResources();
      await listResources();
      await listResourceTemplates();
      await listResourceTemplates();
      await readResource('file:///cached');
      await readResource('file:///cached');

      expect(server.calls, {
        DiscoverRequest.methodName: 1,
        ListToolsRequest.methodName: 1,
        ListPromptsRequest.methodName: 1,
        ListResourcesRequest.methodName: 1,
        ListResourceTemplatesRequest.methodName: 1,
        ReadResourceRequest.methodName: 1,
      });
    });

    test('uses positive ttl until expiry and requires a scope', () async {
      connection.pauseCachedResponseClock();
      server.ttlMs = 0;
      await listTools();
      await listTools();
      expect(server.calls[ListToolsRequest.methodName], 2);

      server.ttlMs = 20;
      await listPrompts();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await listPrompts();
      expect(server.calls[ListPromptsRequest.methodName], 1);
      connection.elapseCachedResponses(const Duration(milliseconds: 21));
      await listPrompts();
      expect(server.calls[ListPromptsRequest.methodName], 2);

      server.ttlMs = 60000;
      server.cacheScope = null;
      await listResources();
      await listResources();
      expect(server.calls[ListResourcesRequest.methodName], 2);

      server
        ..ttlMs = null
        ..cacheScope = CacheScope.private;
      await listResourceTemplates();
      await listResourceTemplates();
      expect(server.calls[ListResourceTemplatesRequest.methodName], 2);

      server
        ..ttlMs = 60000
        ..cacheScope = CacheScope.public;
      await readResource('file:///public');
      await readResource('file:///public');
      expect(server.readCalls['file:///public'], 1);
    });

    test('bypasses the cache for unknown metadata', () async {
      expect((await listTools()).tools.single.name, 'tool-1');

      final request = ListToolsRequest(
        meta: MetaWithProgressToken.fromMap({
          Keys.protocolVersionMeta: ProtocolVersion.v2026_07_28.versionString,
          Keys.progressToken: ProgressToken(1),
        }),
      );
      expect((await connection.listTools(request)).tools.single.name, 'tool-2');
      expect((await connection.listTools(request)).tools.single.name, 'tool-3');
      expect((await listTools()).tools.single.name, 'tool-1');

      expect(server.calls[ListToolsRequest.methodName], 3);
    });

    test('returns responses with malformed cache hints', () async {
      for (final field in [Keys.ttlMs, Keys.cacheScope]) {
        server.malformedHint = field;
        await listTools(Cursor(field));
        await listTools(Cursor(field));
      }
      server.malformedHint = null;

      expect(server.calls[ListToolsRequest.methodName], 4);
    });

    test('uses the configured cache size', () async {
      connection.maxCachedResponses = 2;
      for (var i = 0; i <= 2; i++) {
        await readResource('file:///$i');
      }
      await readResource('file:///0');

      expect(server.readCalls['file:///0'], 2);
    });

    test('shares an in-flight request', () async {
      final result = Completer<ListToolsResult>();
      server.listToolsResult = (_, _) => result.future;

      final first = listTools();
      await pumpEventQueue();
      final second = listTools();
      await pumpEventQueue();
      expect(server.calls[ListToolsRequest.methodName], 1);

      result.complete(server.completeTools(1));
      final responses = await Future.wait([first, second]);
      expect(responses.map((response) => response.tools.single.name), [
        'tool-1',
        'tool-1',
      ]);
      expect(server.calls[ListToolsRequest.methodName], 1);
    });

    test('retries after an in-flight result is not cacheable', () async {
      final result = Completer<ListToolsResult>();
      server.listToolsResult = (_, _) => result.future;

      final first = listTools();
      await pumpEventQueue();
      final second = listTools();
      await pumpEventQueue();
      expect(server.calls[ListToolsRequest.methodName], 1);

      server.ttlMs = 0;
      result.complete(server.completeTools(1));
      await Future.wait([first, second]);
      expect(server.calls[ListToolsRequest.methodName], 2);
    });

    test('separates methods, cursors, and resource uris', () async {
      await listTools(Cursor('page-1'));
      await listTools(Cursor('page-1'));
      await listTools(Cursor('page-2'));
      await listTools(Cursor('page-2'));
      expect(server.calls[ListToolsRequest.methodName], 2);

      await readResource('file:///first');
      await readResource('file:///first');
      await readResource('file:///second');
      await readResource('file:///second');
      expect(server.readCalls, {'file:///first': 1, 'file:///second': 1});
    });

    test('invalid cursor evicts cached list pages', () async {
      expect((await listTools()).tools.single.name, 'tool-1');
      expect((await listTools()).tools.single.name, 'tool-1');

      final validPage = Cursor('valid');
      expect((await listTools(validPage)).tools.single.name, 'tool-2');
      expect((await listTools(validPage)).tools.single.name, 'tool-2');

      final cursor = Cursor('expired');
      server.errorToolCursor = cursor;
      server.toolCursorErrorCode = error_code.INVALID_PARAMS;
      await expectLater(
        listTools(cursor),
        throwsA(
          isA<RpcException>().having(
            (error) => error.code,
            'code',
            error_code.INVALID_PARAMS,
          ),
        ),
      );

      server.errorToolCursor = null;
      expect((await listTools()).tools.single.name, 'tool-4');
      expect((await listTools(validPage)).tools.single.name, 'tool-5');
      expect(server.calls[ListToolsRequest.methodName], 5);
    });

    test('other RPC errors preserve cached list pages', () async {
      final validPage = Cursor('valid');
      expect((await listTools(validPage)).tools.single.name, 'tool-1');
      expect((await listTools(validPage)).tools.single.name, 'tool-1');

      final cursor = Cursor('failed');
      server.errorToolCursor = cursor;
      server.toolCursorErrorCode = error_code.INTERNAL_ERROR;
      await expectLater(
        listTools(cursor),
        throwsA(
          isA<RpcException>().having(
            (error) => error.code,
            'code',
            error_code.INTERNAL_ERROR,
          ),
        ),
      );

      server.errorToolCursor = null;
      expect((await listTools(validPage)).tools.single.name, 'tool-1');
      expect(server.calls[ListToolsRequest.methodName], 2);
    });

    test('does not cache an input_required result', () async {
      // `resources/read` is cacheable, and the same payload may carry the
      // `ttlMs` / `cacheScope` hints together with `resultType:
      // input_required`. Interim results are not cacheable.
      // https://modelcontextprotocol.io/specification/2026-07-28/server/utilities/caching
      server.readResult =
          (_, _) => ReadResourceResult.fromMap({
            Keys.resultType: ResultTypes.inputRequired,
            Keys.contents: [
              TextResourceContents(uri: 'file:///interim', text: 'secret'),
            ],
            Keys.ttlMs: 60000,
            Keys.cacheScope: CacheScope.private.name,
          });
      expect(
        (await readResource('file:///interim')).resultType,
        ResultTypes.inputRequired,
      );
      await readResource('file:///interim');
      expect(server.readCalls['file:///interim'], 2);
    });

    test('does not cache input-required retries', () async {
      server.readResult = server.completeRead;
      final withState = ReadResourceRequest(
        uri: 'file:///state-retry',
        requestState: 'state',
        meta: meta,
      );
      await connection.readResource(withState);
      await connection.readResource(withState);
      expect(server.readCalls['file:///state-retry'], 2);

      final withResponses = ReadResourceRequest(
        uri: 'file:///response-retry',
        inputResponses: {
          'answer': ElicitResult(action: ElicitationAction.decline),
        },
        meta: meta,
      );
      await connection.readResource(withResponses);
      await connection.readResource(withResponses);
      expect(server.readCalls['file:///response-retry'], 2);

      // A server which leaves `resultType` out is read as answering
      // `complete`, so the fields the client retries with are what mark these
      // two interim.
      for (final interim in [
        {
          Keys.inputRequests: <String, Object?>{
            'answer': InputRequest.listRoots(ListRootsRequest()),
          },
        },
        {Keys.requestState: 'state'},
      ]) {
        server.readResult =
            (_, _) => InputRequiredResult.fromMap({
              ...interim,
              Keys.ttlMs: 60000,
              Keys.cacheScope: CacheScope.private.name,
            });
        final uri = 'file:///${interim.keys.single}';
        await readResource(uri);
        await readResource(uri);
        expect(server.readCalls[uri], 2);
      }

      // A paginated request keys on its cursor, and a retry of one carries
      // the same cursor, so only the parameters it adds keep the two apart.
      final listRetry = ListToolsRequest.fromMap({
        Keys.cursor: Cursor('page-1'),
        Keys.requestState: 'state',
        Keys.meta: meta,
      });
      await connection.listTools(listRetry);
      await connection.listTools(listRetry);
      expect(server.calls[ListToolsRequest.methodName], 2);
    });

    test('reuses a result when the handshake settled the revision', () async {
      // Only `discover` names the revision in its own metadata, so a plain
      // call has to lean on the version the handshake settled.
      connection.protocolVersion = ProtocolVersion.v2026_07_28;
      await connection.listTools(ListToolsRequest(meta: null));
      await connection.listTools(ListToolsRequest(meta: null));

      expect(server.calls[ListToolsRequest.methodName], 1);
    });

    test('invalidates entries when change notifications arrive', () async {
      await listTools();
      await listPrompts();
      await listResources();
      await listResourceTemplates();
      await readResource('file:///first');
      await readResource('file:///second');

      server
        ..sendNotification(
          ToolListChangedNotification.methodName,
          ToolListChangedNotification(),
        )
        ..sendNotification(
          PromptListChangedNotification.methodName,
          PromptListChangedNotification(),
        )
        ..sendNotification(
          ResourceListChangedNotification.methodName,
          ResourceListChangedNotification(),
        )
        ..sendNotification(
          ResourceUpdatedNotification.methodName,
          ResourceUpdatedNotification(uri: 'file:///first'),
        );
      await pumpEventQueue();

      await listTools();
      await listPrompts();
      await listResources();
      await listResourceTemplates();
      await readResource('file:///first');
      await readResource('file:///second');

      expect(server.calls[ListToolsRequest.methodName], 2);
      expect(server.calls[ListPromptsRequest.methodName], 2);
      expect(server.calls[ListResourcesRequest.methodName], 2);
      expect(server.calls[ListResourceTemplatesRequest.methodName], 2);
      expect(server.readCalls, {'file:///first': 2, 'file:///second': 1});
    });

    test(
      'invalidates a read whose contents name the updated resource',
      () async {
        const parent = 'file:///dir';
        const child = 'file:///dir/child';
        // The schema says the updated URI might be a sub-resource of the
        // one subscribed to, and a read can answer with several contents.
        server.readResult =
            (_, count) => ReadResourceResult.fromMap({
              Keys.resultType: ResultTypes.complete,
              Keys.contents: [
                TextResourceContents(uri: child, text: 'read-$count'),
              ],
              Keys.ttlMs: 60000,
              Keys.cacheScope: CacheScope.private.name,
            });
        await readResource(parent);
        await readResource(parent);
        expect(server.readCalls[parent], 1);

        server.sendNotification(
          ResourceUpdatedNotification.methodName,
          ResourceUpdatedNotification(uri: child),
        );
        await pumpEventQueue();

        await readResource(parent);
        expect(server.readCalls[parent], 2);
      },
    );

    test(
      'does not store a read whose contents changed while in flight',
      () async {
        const parent = 'file:///dir';
        const child = 'file:///dir/child';
        final pending = Completer<ReadResourceResult>();
        server.readResult = (_, _) => pending.future;
        final inFlight = readResource(parent);
        await pumpEventQueue();
        expect(server.readCalls[parent], 1);

        server.sendNotification(
          ResourceUpdatedNotification.methodName,
          ResourceUpdatedNotification(uri: child),
        );
        await pumpEventQueue();
        pending.complete(
          ReadResourceResult.fromMap({
            Keys.resultType: ResultTypes.complete,
            Keys.contents: [TextResourceContents(uri: child, text: 'read-1')],
            Keys.ttlMs: 60000,
            Keys.cacheScope: CacheScope.private.name,
          }),
        );
        await inFlight;

        server.readResult = null;
        await readResource(parent);
        expect(server.readCalls[parent], 2);
      },
    );

    test('does not store responses invalidated while in flight', () async {
      final toolsResult = Completer<ListToolsResult>();
      server.listToolsResult = (_, _) => toolsResult.future;
      final pendingTools = listTools();
      await pumpEventQueue();
      expect(server.calls[ListToolsRequest.methodName], 1);

      server.sendNotification(
        ToolListChangedNotification.methodName,
        ToolListChangedNotification(),
      );
      await pumpEventQueue();
      toolsResult.complete(server.completeTools(1));
      await pendingTools;

      server.listToolsResult = null;
      expect((await listTools()).tools.single.name, 'tool-2');
      expect(server.calls[ListToolsRequest.methodName], 2);

      final firstResult = Completer<ReadResourceResult>();
      final secondResult = Completer<ReadResourceResult>();
      const first = 'file:///in-flight';
      const second = 'file:///other-in-flight';
      server.readResult =
          (request, _) =>
              request.uri == first ? firstResult.future : secondResult.future;
      final pendingFirst = readResource(first);
      final pendingSecond = readResource(second);
      await pumpEventQueue();
      expect(server.readCalls, {first: 1, second: 1});

      server.sendNotification(
        ResourceUpdatedNotification.methodName,
        ResourceUpdatedNotification(uri: first),
      );
      await pumpEventQueue();
      firstResult.complete(
        server.completeRead(ReadResourceRequest(uri: first), 1),
      );
      secondResult.complete(
        server.completeRead(ReadResourceRequest(uri: second), 2),
      );
      await Future.wait([pendingFirst, pendingSecond]);

      server.readResult = null;
      final nextFirst = await readResource(first);
      final nextSecond = await readResource(second);
      expect(nextFirst.contents.single, isA<TextResourceContents>());
      expect(
        (nextFirst.contents.single as TextResourceContents).text,
        'read-3',
      );
      expect(nextSecond.contents.single, isA<TextResourceContents>());
      expect(
        (nextSecond.contents.single as TextResourceContents).text,
        'read-2',
      );
      expect(server.readCalls, {first: 2, second: 1});
    });

    test('returns copies of cached response maps', () async {
      server.resultMeta = Meta.fromMap({
        'com.example/nested': <Object?, Object?>{'value': 1},
      });
      final first = await listTools();
      (first.tools.single as Map<String, Object?>)[Keys.name] = 'changed';
      first.tools.clear();
      (first.meta!['com.example/nested'] as Map)['value'] = 2;

      final second = await listTools();
      expect(second.tools, hasLength(1));
      expect(second.tools.single.name, 'tool-1');
      expect((second.meta!['com.example/nested'] as Map)['value'], 1);
      (second.tools.single as Map<String, Object?>)[Keys.name] =
          'changed-again';

      final third = await listTools();
      expect(third.tools.single.name, 'tool-1');
      expect(server.calls[ListToolsRequest.methodName], 1);
    });

    test('sends every request naming an earlier revision', () async {
      final legacy = ListToolsRequest(
        meta: MetaWithProgressToken.fromMap({
          Keys.protocolVersionMeta: ProtocolVersion.v2025_11_25.versionString,
        }),
      );

      await connection.listTools(legacy);
      await connection.listTools(legacy);

      expect(server.calls[ListToolsRequest.methodName], 2);
    });

    test('an invalid cursor on a bypassed request evicts pages', () async {
      final page = Cursor('page-1');
      expect((await listTools(page)).tools.single.name, 'tool-1');
      expect((await listTools(page)).tools.single.name, 'tool-1');

      final cursor = Cursor('expired');
      server.errorToolCursor = cursor;
      server.toolCursorErrorCode = error_code.INVALID_PARAMS;
      await expectLater(
        connection.listTools(
          ListToolsRequest.fromMap({
            Keys.cursor: cursor,
            Keys.meta: {
              Keys.protocolVersionMeta:
                  ProtocolVersion.v2026_07_28.versionString,
              'com.example/unknown': true,
            },
          }),
        ),
        throwsA(isA<RpcException>()),
      );

      server.errorToolCursor = null;
      expect((await listTools(page)).tools.single.name, 'tool-3');
      expect(server.calls[ListToolsRequest.methodName], 3);
    });

    test('a zero ttl does not take a cache slot', () async {
      await readResource('file:///kept');

      server.ttlMs = 0;
      for (var i = 0; i <= 512; i++) {
        await readResource('file:///stale-$i');
      }

      server.ttlMs = 60000;
      await readResource('file:///kept');

      expect(server.readCalls['file:///kept'], 1);
    });

    test('clamps a ttl which overflows a duration', () async {
      // `Duration(milliseconds: 9223372036854775807)` is negative, so an
      // unclamped entry would already be stale when it is written.
      server.ttlMs = 9223372036854775807;

      await listTools();
      await listTools();

      expect(server.calls[ListToolsRequest.methodName], 1);
    });

    test('saturates an expiry which overflows a duration', () async {
      connection
        ..maxCachedResponseTtl = const Duration(
          microseconds: 9223372036854775807,
        )
        ..pauseCachedResponseClock();
      server.ttlMs = 9223372036854775807;

      await listTools();
      await listTools();

      expect(server.calls[ListToolsRequest.methodName], 1);
    });

    test('defaults the maximum ttl to a day', () async {
      connection.pauseCachedResponseClock();
      server.ttlMs = const Duration(hours: 36).inMilliseconds;

      await listTools();
      connection.elapseCachedResponses(
        const Duration(hours: 24) - const Duration(seconds: 1),
      );
      await listTools();
      expect(server.calls[ListToolsRequest.methodName], 1);

      connection.elapseCachedResponses(const Duration(seconds: 2));
      await listTools();
      expect(server.calls[ListToolsRequest.methodName], 2);
    });

    test('uses the configured maximum ttl', () async {
      connection
        ..maxCachedResponseTtl = const Duration(hours: 1)
        ..pauseCachedResponseClock();
      server.ttlMs = const Duration(hours: 2).inMilliseconds;

      await listTools();
      connection.elapseCachedResponses(const Duration(hours: 1));
      await listTools();
      expect(server.calls[ListToolsRequest.methodName], 2);
    });

    test('changing the maximum ttl clears cached responses', () async {
      await listTools();
      expect(connection.cachedResponseCount, 1);

      connection.maxCachedResponseTtl = const Duration(hours: 1);
      expect(connection.cachedResponseCount, 0);
      await listTools();

      expect(server.calls[ListToolsRequest.methodName], 2);
    });

    test('a zero maximum ttl disables response caching', () async {
      await listTools();
      connection.maxCachedResponseTtl = Duration.zero;

      await listTools();
      await listTools();

      expect(connection.cachedResponseCount, 0);
      expect(server.calls[ListToolsRequest.methodName], 3);
    });

    test('drops cached entries on shutdown', () async {
      await listTools();
      await listTools();
      expect(server.calls[ListToolsRequest.methodName], 1);
      expect(connection.cachedResponseCount, 1);

      await connection.shutdown();
      expect(connection.cachedResponseCount, 0);
    });
  });
}

final class _RequestScopedCacheServer extends TestMCPServer {
  _RequestScopedCacheServer(super.channel, this.calls) {
    registerRequestHandler<ListToolsRequest?, ListToolsResult>(
      ListToolsRequest.methodName,
      _listTools,
    );
  }

  final Map<String, int> calls;

  ListToolsResult _listTools(ListToolsRequest? _) {
    final count = calls.update(
      ListToolsRequest.methodName,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    return ListToolsResult(
      tools: [Tool(name: 'tool-$count', inputSchema: ObjectSchema())],
      ttlMs: 60000,
      cacheScope: CacheScope.private,
    );
  }
}

final class _CacheServer extends TestMCPServer {
  _CacheServer(super.channel) {
    registerRequestHandler<DiscoverRequest?, DiscoverResult>(
      DiscoverRequest.methodName,
      _discover,
    );
    registerRequestHandler<ListToolsRequest?, ListToolsResult>(
      ListToolsRequest.methodName,
      _listTools,
    );
    registerRequestHandler<ListPromptsRequest?, ListPromptsResult>(
      ListPromptsRequest.methodName,
      _listPrompts,
    );
    registerRequestHandler<ListResourcesRequest?, ListResourcesResult>(
      ListResourcesRequest.methodName,
      _listResources,
    );
    registerRequestHandler<
      ListResourceTemplatesRequest?,
      ListResourceTemplatesResult
    >(ListResourceTemplatesRequest.methodName, _listResourceTemplates);
    registerRequestHandler<ReadResourceRequest, Result>(
      ReadResourceRequest.methodName,
      _readResource,
    );
  }

  final calls = <String, int>{};
  final readCalls = <String, int>{};
  int? ttlMs = 60000;
  CacheScope? cacheScope = CacheScope.private;
  bool includeResultType = true;
  Cursor? errorToolCursor;
  int? toolCursorErrorCode;
  Meta? resultMeta;
  String? malformedHint;
  FutureOr<ListToolsResult> Function(ListToolsRequest?, int)? listToolsResult;
  FutureOr<Result> Function(ReadResourceRequest, int)? readResult;

  int _record(String methodName) =>
      calls.update(methodName, (count) => count + 1, ifAbsent: () => 1);

  T _complete<T extends Result>(T result) {
    if (includeResultType) {
      (result as Map<String, Object?>)[Keys.resultType] = ResultTypes.complete;
    }
    if (malformedHint case final field?) {
      (result as Map<String, Object?>)[field] = false;
    }
    return result;
  }

  DiscoverResult _discover(DiscoverRequest? _) {
    _record(DiscoverRequest.methodName);
    return _complete(
      DiscoverResult(
        supportedVersions: [ProtocolVersion.v2026_07_28.versionString],
        capabilities: ServerCapabilities(),
        ttlMs: ttlMs,
        cacheScope: cacheScope,
      ),
    );
  }

  FutureOr<ListToolsResult> _listTools(ListToolsRequest? request) {
    final count = _record(ListToolsRequest.methodName);
    final cursor = request?.cursor;
    if (errorToolCursor != null && cursor == errorToolCursor) {
      throw RpcException(
        toolCursorErrorCode!,
        'The cursor "$cursor" failed. Every other cursor is valid.',
      );
    }
    return listToolsResult?.call(request, count) ?? completeTools(count);
  }

  ListToolsResult completeTools(int count) {
    return _complete(
      ListToolsResult(
        tools: [Tool(name: 'tool-$count', inputSchema: ObjectSchema())],
        ttlMs: ttlMs,
        cacheScope: cacheScope,
        meta: resultMeta,
      ),
    );
  }

  ListPromptsResult _listPrompts(ListPromptsRequest? _) {
    final count = _record(ListPromptsRequest.methodName);
    return _complete(
      ListPromptsResult(
        prompts: [Prompt(name: 'prompt-$count')],
        ttlMs: ttlMs,
        cacheScope: cacheScope,
      ),
    );
  }

  ListResourcesResult _listResources(ListResourcesRequest? _) {
    final count = _record(ListResourcesRequest.methodName);
    return _complete(
      ListResourcesResult(
        resources: [Resource(uri: 'file:///$count', name: 'resource-$count')],
        ttlMs: ttlMs,
        cacheScope: cacheScope,
      ),
    );
  }

  ListResourceTemplatesResult _listResourceTemplates(
    ListResourceTemplatesRequest? _,
  ) {
    final count = _record(ListResourceTemplatesRequest.methodName);
    return _complete(
      ListResourceTemplatesResult(
        resourceTemplates: [
          ResourceTemplate(
            uriTemplate: 'file:///{name}',
            name: 'template-$count',
          ),
        ],
        ttlMs: ttlMs,
        cacheScope: cacheScope,
      ),
    );
  }

  FutureOr<Result> _readResource(ReadResourceRequest request) {
    final count = _record(ReadResourceRequest.methodName);
    readCalls.update(request.uri, (count) => count + 1, ifAbsent: () => 1);
    return readResult?.call(request, count) ?? completeRead(request, count);
  }

  ReadResourceResult completeRead(ReadResourceRequest request, int count) =>
      _complete(
        ReadResourceResult(
          contents: [
            TextResourceContents(uri: request.uri, text: 'read-$count'),
          ],
          ttlMs: ttlMs,
          cacheScope: cacheScope,
        ),
      );
}
