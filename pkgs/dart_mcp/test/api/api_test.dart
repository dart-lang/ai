// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_mcp/client.dart';
import 'package:test/test.dart';

void main() {
  // A getter reads the same null whether the key was omitted or written as
  // null, so these assert on the map.
  test('metadata and meta leave out what they are not given', () {
    expect(BaseMetadata(name: 'n') as Map<String, Object?>, {'name': 'n'});
    expect(BaseMetadata(name: 'n', title: 't') as Map<String, Object?>, {
      'name': 'n',
      'title': 't',
    });
    expect(MetaWithProgressToken() as Map<String, Object?>, isEmpty);
    expect(
      MetaWithProgressToken(progressToken: ProgressToken(1))
          as Map<String, Object?>,
      {'progressToken': 1},
    );
  });

  test('protocol versions can be compared', () {
    expect(
      ProtocolVersion.latestSupported > ProtocolVersion.oldestSupported,
      true,
    );
    expect(
      ProtocolVersion.latestSupported >= ProtocolVersion.oldestSupported,
      true,
    );
    expect(
      ProtocolVersion.latestSupported < ProtocolVersion.oldestSupported,
      false,
    );
    expect(
      ProtocolVersion.latestSupported <= ProtocolVersion.oldestSupported,
      false,
    );

    expect(
      ProtocolVersion.oldestSupported > ProtocolVersion.latestSupported,
      false,
    );
    expect(
      ProtocolVersion.oldestSupported >= ProtocolVersion.latestSupported,
      false,
    );
    expect(
      ProtocolVersion.oldestSupported < ProtocolVersion.latestSupported,
      true,
    );
    expect(
      ProtocolVersion.oldestSupported <= ProtocolVersion.latestSupported,
      true,
    );

    expect(
      ProtocolVersion.latestSupported <= ProtocolVersion.latestSupported,
      true,
    );
    expect(
      ProtocolVersion.latestSupported >= ProtocolVersion.latestSupported,
      true,
    );
    expect(
      ProtocolVersion.latestSupported < ProtocolVersion.latestSupported,
      false,
    );
    expect(
      ProtocolVersion.latestSupported > ProtocolVersion.latestSupported,
      false,
    );
  });

  test('the legacy handshake does not support the request-scoped era', () {
    // The 2026-07-28 revision is spoken by its own transport; the legacy
    // handshake refusing it is what downgrades a modern server talking to a
    // legacy client, so this must stay false until that handshake learns
    // the revision.
    expect(ProtocolVersion.v2026_07_28.isSupported, false);
    expect(ProtocolVersion.v2026_07_28 > ProtocolVersion.latestSupported, true);
  });

  test('a method holds from the revision which added it', () {
    expect(ProtocolVersion.v2024_11_05.methodIsValid('tools/call'), true);
    expect(ProtocolVersion.v2026_07_28.methodIsValid('tools/call'), true);
    expect(
      ProtocolVersion.v2025_03_26.methodIsValid('elicitation/create'),
      false,
    );
    expect(
      ProtocolVersion.v2025_06_18.methodIsValid('elicitation/create'),
      true,
    );
    expect(ProtocolVersion.v2025_11_25.methodIsValid('server/discover'), false);
    expect(ProtocolVersion.v2026_07_28.methodIsValid('server/discover'), true);
  });

  test('the 2026-07-28 revision removes what its schema removed', () {
    // Pinned against the schema so an entry cannot fall out of the set
    // unnoticed; the walk test below reads the set and would follow it.
    expect(ProtocolVersion.v2026_07_28.removedMethods, {
      'initialize',
      'logging/setLevel',
      'notifications/elicitation/complete',
      'notifications/initialized',
      'notifications/roots/list_changed',
      'notifications/tasks/status',
      'ping',
      'resources/subscribe',
      'resources/unsubscribe',
      'tasks/cancel',
      'tasks/get',
      'tasks/list',
      'tasks/result',
    });
  });

  test('a method ends at the revision which removed it', () {
    for (var method in ProtocolVersion.v2026_07_28.removedMethods) {
      expect(
        ProtocolVersion.v2025_11_25.methodIsValid(method),
        true,
        reason: '$method on 2025-11-25',
      );
      expect(
        ProtocolVersion.v2026_07_28.methodIsValid(method),
        false,
        reason: '$method on 2026-07-28',
      );
    }
  });

  test('a method no revision defines is not valid on any of them', () {
    for (var version in ProtocolVersion.values) {
      expect(version.methodIsValid('no/such/method'), false);
    }
  });

  group('API object validation', () {
    test('throws when required fields are missing', () {
      expect(() => Root.fromMap({}).uri, throwsA(isA<ArgumentError>()));
      expect(
        () => Implementation.fromMap({'name': 'test'}).version,
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => BaseMetadata.fromMap({}).name,
        throwsA(isA<ArgumentError>()),
      );

      final empty = <String, Object?>{};

      // Initialization
      expect(
        () => (empty as InitializeRequest).capabilities,
        throwsArgumentError,
      );
      expect(
        () => (empty as InitializeRequest).clientInfo,
        throwsArgumentError,
      );
      expect(
        () => (empty as DiscoverResult).supportedVersions,
        throwsArgumentError,
      );
      expect(() => (empty as DiscoverResult).capabilities, throwsArgumentError);

      // Tools
      expect(() => (empty as CallToolRequest).name, throwsArgumentError);

      // Resources
      expect(() => (empty as ReadResourceRequest).uri, throwsArgumentError);
      expect(() => (empty as SubscribeRequest).uri, throwsArgumentError);
      expect(() => (empty as UnsubscribeRequest).uri, throwsArgumentError);

      // Roots
      expect(() => (empty as ListRootsResult).roots, throwsArgumentError);

      // Prompts
      expect(() => (empty as GetPromptRequest).name, throwsArgumentError);

      // Completions
      expect(() => (empty as CompleteRequest).ref, throwsArgumentError);
      expect(() => (empty as CompleteRequest).argument, throwsArgumentError);

      // Logging
      expect(() => (empty as SetLevelRequest).level, throwsArgumentError);

      // Sampling
      expect(
        () => (empty as CreateMessageRequest).messages,
        throwsArgumentError,
      );
      expect(
        () => (empty as CreateMessageRequest).maxTokens,
        throwsArgumentError,
      );
    });
    test('meta field is parsed correctly', () {
      final root = Root.fromMap({
        'uri': 'file:///foo/bar',
        '_meta': {'foo': 'bar'},
      });
      expect(root.meta, isNotNull);
      final metaMap = root.meta as Map;
      expect(metaMap['foo'], 'bar');
    });
    test('resultType defaults to complete when absent and passes strings '
        'through', () {
      expect((<String, Object?>{} as Result).resultType, 'complete');
      expect(
        (<String, Object?>{'resultType': 'input_required'} as Result)
            .resultType,
        'input_required',
      );
      expect(
        (<String, Object?>{'resultType': 'streaming'} as Result).resultType,
        'streaming',
      );
    });
    test('cacheable result fields default when absent and parse known '
        'values', () {
      final empty = <String, Object?>{} as CacheableResult;
      expect(empty.ttlMs, 0);
      expect(empty.cacheScope, null);
      expect((<String, Object?>{'ttlMs': -5} as CacheableResult).ttlMs, 0);
      final cacheable =
          <String, Object?>{'ttlMs': 5000, 'cacheScope': 'private'}
              as CacheableResult;
      expect(cacheable.ttlMs, 5000);
      expect(cacheable.cacheScope, CacheScope.private);
      expect(
        (<String, Object?>{'cacheScope': 'public'} as CacheableResult)
            .cacheScope,
        CacheScope.public,
      );
      expect(
        (<String, Object?>{'cacheScope': 'session'} as CacheableResult)
            .cacheScope,
        null,
      );
      final listTools =
          <String, Object?>{
                'tools': <Object?>[],
                'ttlMs': 5000,
                'cacheScope': 'public',
              }
              as ListToolsResult;
      expect(listTools.ttlMs, 5000);
      expect(listTools.cacheScope, CacheScope.public);
    });
    test('request ids round trip both JSON-RPC id types', () {
      for (var id in <Object>[7, 'abc']) {
        final cancelled = CancelledNotification(requestId: RequestId(id));
        expect(
          cancelled as Map<String, Object?>,
          containsPair('requestId', id),
        );
        expect(cancelled.requestId, id);
      }
    });
  });

  group('cacheable result factory', () {
    // Returns an instance of every cacheable result type with the given
    // settings. The tests assert on the map rather than the getters: an absent
    // `ttlMs` and a written `ttlMs: 0` both read as `0`.
    List<Map<String, Object?>> cacheable({
      int? ttlMs,
      CacheScope? cacheScope,
    }) =>
        [
          ListToolsResult(tools: [], ttlMs: ttlMs, cacheScope: cacheScope),
          ListPromptsResult(prompts: [], ttlMs: ttlMs, cacheScope: cacheScope),
          ListResourcesResult(
            resources: [],
            ttlMs: ttlMs,
            cacheScope: cacheScope,
          ),
          ListResourceTemplatesResult(
            resourceTemplates: [],
            ttlMs: ttlMs,
            cacheScope: cacheScope,
          ),
          ReadResourceResult(
            contents: [],
            ttlMs: ttlMs,
            cacheScope: cacheScope,
          ),
          DiscoverResult(
            supportedVersions: [],
            capabilities: ServerCapabilities(),
            ttlMs: ttlMs,
            cacheScope: cacheScope,
          ),
        ].cast<Map<String, Object?>>();

    test('writes the hints it is given', () {
      for (var result in cacheable(
        ttlMs: 5000,
        cacheScope: CacheScope.public,
      )) {
        expect(result, containsPair('ttlMs', 5000));
        expect(result, containsPair('cacheScope', 'public'));
      }
      for (var result in cacheable(ttlMs: 0, cacheScope: CacheScope.private)) {
        expect(result, containsPair('ttlMs', 0));
        expect(result, containsPair('cacheScope', 'private'));
      }
    });

    test('writes only the hint it is given', () {
      for (var result in cacheable(ttlMs: 5000)) {
        expect(result, containsPair('ttlMs', 5000));
        expect(result, isNot(contains('cacheScope')));
      }
      for (var result in cacheable(cacheScope: CacheScope.public)) {
        expect(result, containsPair('cacheScope', 'public'));
        expect(result, isNot(contains('ttlMs')));
      }
    });

    test('leaves out the hints it is not given', () {
      for (var result in cacheable()) {
        expect(result, isNot(contains('ttlMs')));
        expect(result, isNot(contains('cacheScope')));
      }
    });
  });
}
