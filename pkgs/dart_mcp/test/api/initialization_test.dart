// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:dart_mcp/server.dart';
import 'package:test/test.dart';

void main() {
  test('null instructions', () async {
    final result = InitializeResult(
      protocolVersion: ProtocolVersion.latestSupported,
      serverCapabilities: ServerCapabilities(),
      serverInfo: Implementation(name: 'name', version: 'version'),
    );

    final map = result as Map<String, Object?>;
    expect(map.containsKey('instructions'), isFalse);
  });

  test('nonnull instructions', () async {
    final result = InitializeResult(
      protocolVersion: ProtocolVersion.latestSupported,
      serverCapabilities: ServerCapabilities(),
      serverInfo: Implementation(name: 'name', version: 'version'),
      instructions: 'foo',
    );

    final map = result as Map<String, Object?>;
    expect(map['instructions'], equals('foo'));
  });

  // The factory tests assert on the map rather than on the getters, so that a
  // field the factory never wrote cannot be mistaken for one it wrote.
  group('server/discover', () {
    test('the request carries no parameters of its own', () {
      expect(DiscoverRequest() as Map<String, Object?>, isEmpty);
    });

    test('the request writes the metadata it is given', () {
      final request =
          DiscoverRequest(
                meta: MetaWithProgressToken(progressToken: ProgressToken(1)),
              )
              as Map<String, Object?>;

      expect(request['_meta'], containsPair('progressToken', ProgressToken(1)));
    });

    test('the result writes the fields it is given', () {
      final result =
          DiscoverResult(
                supportedVersions: ['2026-07-28'],
                capabilities: ServerCapabilities(tools: Tools()),
                instructions: 'Prefer `get_weather` for forecast lookups.',
                meta: Meta.fromMap({
                  'io.modelcontextprotocol/serverInfo': Implementation(
                    name: 'name',
                    version: 'version',
                  ),
                }),
              )
              as Map<String, Object?>;

      expect(result, containsPair('supportedVersions', ['2026-07-28']));
      expect(result['capabilities'], containsPair('tools', isEmpty));
      expect(
        result,
        containsPair(
          'instructions',
          'Prefer `get_weather` for forecast lookups.',
        ),
      );
      expect(
        result['_meta'],
        containsPair(
          'io.modelcontextprotocol/serverInfo',
          containsPair('name', 'name'),
        ),
      );
    });

    test('the result leaves out the fields it is not given', () {
      final result =
          DiscoverResult(
                supportedVersions: ['2026-07-28'],
                capabilities: ServerCapabilities(),
              )
              as Map<String, Object?>;

      expect(result, isNot(contains('instructions')));
      expect(result, isNot(contains('_meta')));
    });

    test('the result reads its fields back off a decoded map', () {
      final result = DiscoverResult.fromMap(
        jsonDecode('''
{
  "supportedVersions": ["2026-07-28"],
  "capabilities": {"tools": {}},
  "instructions": "Prefer `get_weather` for forecast lookups."
}
''')
            as Map<String, Object?>,
      );

      expect(result.supportedVersions, ['2026-07-28']);
      expect(result.capabilities.tools, isNotNull);
      expect(result.instructions, 'Prefer `get_weather` for forecast lookups.');
    });

    test('the result reports a version this package does not know', () {
      // The point of reading these as strings: dropping the versions
      // `ProtocolVersion` has no name for would hide them from the client
      // that has to choose one.
      expect(ProtocolVersion.tryParse('2027-11-05'), isNull);

      final result = DiscoverResult.fromMap({
        'supportedVersions': ['2026-07-28', '2027-11-05'],
        'capabilities': ServerCapabilities(),
      });

      expect(result.supportedVersions, ['2026-07-28', '2027-11-05']);
    });
  });

  group('capability extensions', () {
    test('client capabilities round trip an extensions map', () {
      final capabilities = ClientCapabilities(
        extensions: {'io.modelcontextprotocol/oauth-client-credentials': {}},
      );

      final map = capabilities as Map<String, Object?>;
      expect(map['extensions'], {
        'io.modelcontextprotocol/oauth-client-credentials': <String, Object?>{},
      });
      expect(capabilities.extensions, {
        'io.modelcontextprotocol/oauth-client-credentials': <String, Object?>{},
      });
    });

    test('client capabilities omit extensions when unset', () {
      final capabilities = ClientCapabilities();

      final map = capabilities as Map<String, Object?>;
      expect(map.containsKey('extensions'), isFalse);
      expect(capabilities.extensions, isNull);
    });

    test('server capabilities round trip an extensions map', () {
      final capabilities = ServerCapabilities(
        extensions: {'io.modelcontextprotocol/tasks': {}},
      );

      final map = capabilities as Map<String, Object?>;
      expect(map['extensions'], {
        'io.modelcontextprotocol/tasks': <String, Object?>{},
      });
      expect(capabilities.extensions, {
        'io.modelcontextprotocol/tasks': <String, Object?>{},
      });
    });

    test('server capabilities omit extensions when unset', () {
      final capabilities = ServerCapabilities();

      final map = capabilities as Map<String, Object?>;
      expect(map.containsKey('extensions'), isFalse);
      expect(capabilities.extensions, isNull);
    });

    test('client capabilities set extensions once', () {
      final capabilities = ClientCapabilities();
      capabilities.extensions = {
        'io.modelcontextprotocol/oauth-client-credentials': {},
      };

      expect(capabilities.extensions, {
        'io.modelcontextprotocol/oauth-client-credentials': <String, Object?>{},
      });
      expect(
        () => capabilities.extensions = {'io.modelcontextprotocol/tasks': {}},
        throwsA(isA<AssertionError>()),
      );
      // A compiled executable has asserts stripped, so there is nothing to
      // catch there.
    }, testOn: '!exe');

    test('server capabilities set extensions once', () {
      final capabilities = ServerCapabilities();
      capabilities.extensions = {'io.modelcontextprotocol/tasks': {}};

      expect(capabilities.extensions, {
        'io.modelcontextprotocol/tasks': <String, Object?>{},
      });
      expect(
        () => capabilities.extensions = {'io.modelcontextprotocol/other': {}},
        throwsA(isA<AssertionError>()),
      );
    }, testOn: '!exe');
  });
}
