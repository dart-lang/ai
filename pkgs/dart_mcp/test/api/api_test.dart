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
  });
}
