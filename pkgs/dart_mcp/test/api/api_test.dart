// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:checks/checks.dart';
import 'package:dart_mcp/client.dart';
import 'package:test/test.dart';

void main() {
  test('protocol versions can be compared', () {
    check(
      ProtocolVersion.latestSupported > ProtocolVersion.oldestSupported,
    ).isTrue();
    check(
      ProtocolVersion.latestSupported >= ProtocolVersion.oldestSupported,
    ).isTrue();
    check(
      ProtocolVersion.latestSupported < ProtocolVersion.oldestSupported,
    ).isFalse();
    check(
      ProtocolVersion.latestSupported <= ProtocolVersion.oldestSupported,
    ).isFalse();

    check(
      ProtocolVersion.oldestSupported > ProtocolVersion.latestSupported,
    ).isFalse();
    check(
      ProtocolVersion.oldestSupported >= ProtocolVersion.latestSupported,
    ).isFalse();
    check(
      ProtocolVersion.oldestSupported < ProtocolVersion.latestSupported,
    ).isTrue();
    check(
      ProtocolVersion.oldestSupported <= ProtocolVersion.latestSupported,
    ).isTrue();

    check(
      ProtocolVersion.latestSupported <= ProtocolVersion.latestSupported,
    ).isTrue();
    check(
      ProtocolVersion.latestSupported >= ProtocolVersion.latestSupported,
    ).isTrue();
    check(
      ProtocolVersion.latestSupported < ProtocolVersion.latestSupported,
    ).isFalse();
    check(
      ProtocolVersion.latestSupported > ProtocolVersion.latestSupported,
    ).isFalse();
  });

  group('API object validation', () {
    test('throws when required fields are missing', () {
      check(() => Root.fromMap({}).uri).throws<ArgumentError>();
      check(
        () => Implementation.fromMap({'name': 'test'}).version,
      ).throws<ArgumentError>();
      check(() => BaseMetadata.fromMap({}).name).throws<ArgumentError>();

      final empty = <String, Object?>{};

      // Initialization
      check(
        () => (empty as InitializeRequest).capabilities,
      ).throws<ArgumentError>();
      check(
        () => (empty as InitializeRequest).clientInfo,
      ).throws<ArgumentError>();

      // Tools
      check(() => (empty as CallToolRequest).name).throws<ArgumentError>();

      // Resources
      check(() => (empty as ReadResourceRequest).uri).throws<ArgumentError>();
      check(() => (empty as SubscribeRequest).uri).throws<ArgumentError>();
      check(() => (empty as UnsubscribeRequest).uri).throws<ArgumentError>();

      // Roots
      check(() => (empty as ListRootsResult).roots).throws<ArgumentError>();

      // Prompts
      check(() => (empty as GetPromptRequest).name).throws<ArgumentError>();

      // Completions
      check(() => (empty as CompleteRequest).ref).throws<ArgumentError>();
      check(() => (empty as CompleteRequest).argument).throws<ArgumentError>();

      // Logging
      check(() => (empty as SetLevelRequest).level).throws<ArgumentError>();

      // Sampling
      check(
        () => (empty as CreateMessageRequest).messages,
      ).throws<ArgumentError>();
      check(
        () => (empty as CreateMessageRequest).maxTokens,
      ).throws<ArgumentError>();
    });
    test('meta field is parsed correctly', () {
      final root = Root.fromMap({
        'uri': 'file:///foo/bar',
        '_meta': {'foo': 'bar'},
      });
      check(root.meta).isNotNull();
      final metaMap = root.meta as Map;
      check(metaMap['foo']).equals('bar');
    });
  });
}
