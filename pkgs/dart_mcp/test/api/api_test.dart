// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_mcp/client.dart';
import 'package:test/test.dart';

void main() {
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
  });
}
