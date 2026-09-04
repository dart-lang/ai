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
  test('ServerCapabilities writes every field it is given', () {
    final capabilities = ServerCapabilities(
      experimental: {'x': 1},
      completions: Completions(),
      logging: Logging(),
      prompts: Prompts(),
      resources: Resources(),
      tools: Tools(),
      extensions: {'example/y': 2},
    );

    final map = capabilities as Map<String, Object?>;
    expect(map.keys, {
      'experimental',
      'completions',
      'logging',
      'prompts',
      'resources',
      'tools',
      'extensions',
    });
  });

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
    final malformedCapabilities = <String, Object?>{
      'extensions': <String, Object?>{'tasks': <String, Object?>{}},
    };
    final extensionWriters =
        <String, void Function(Map<String, Object?> extensions)>{
          'client factory': (extensions) {
            ClientCapabilities(extensions: extensions);
          },
          'client fromMap': (extensions) {
            ClientCapabilities.fromMap({'extensions': extensions});
          },
          'client setter': (extensions) {
            ClientCapabilities().extensions = extensions;
          },
          'server factory': (extensions) {
            ServerCapabilities(extensions: extensions);
          },
          'server fromMap': (extensions) {
            ServerCapabilities.fromMap({'extensions': extensions});
          },
          'server setter': (extensions) {
            ServerCapabilities().extensions = extensions;
          },
        };

    for (final extensionWriter in extensionWriters.entries) {
      test('${extensionWriter.key} rejects malformed identifiers', () {
        for (final identifier in [
          'tasks',
          '9example/tasks',
          'example-/tasks',
          'example/-tasks',
          'example/tasks-',
        ]) {
          expect(
            () => extensionWriter.value({identifier: {}}),
            throwsArgumentError,
            reason: identifier,
          );
        }
      });
    }

    for (final decoder
        in {
          'client fromMap': ClientCapabilities.fromMap,
          'server fromMap': ServerCapabilities.fromMap,
        }.entries) {
      test('${decoder.key} rejects a non-map extensions value', () {
        for (final extensions in <Object?>[
          <Object?>[],
          <Object?, Object?>{1: <String, Object?>{}},
          null,
        ]) {
          expect(
            () => decoder.value(<String, Object?>{'extensions': extensions}),
            throwsArgumentError,
          );
        }
      });
    }

    test('fromMap copies the capability map', () {
      final map = <String, Object?>{
        'extensions': <String, Object?>{'example/tasks': <String, Object?>{}},
      };
      final capabilities = ClientCapabilities.fromMap(map);

      map['extensions'] = <String, Object?>{'tasks': <String, Object?>{}};
      expect(capabilities.extensions, {'example/tasks': <String, Object?>{}});
    });

    test('extension keys cannot change after validation', () {
      final extensions = <String, Object?>{'example/tasks': {}};
      final capabilities = ClientCapabilities(extensions: extensions);

      extensions['tasks'] = {};
      expect(capabilities.extensions, {'example/tasks': <String, Object?>{}});
      expect(
        () => capabilities.extensions!['tasks'] = {},
        throwsUnsupportedError,
      );
    });

    for (final writer
        in <String, Map<String, Object?> Function()>{
          'client setter': () {
            final capabilities = ClientCapabilities()..extensions = null;
            return capabilities as Map<String, Object?>;
          },
          'server setter': () {
            final capabilities = ServerCapabilities()..extensions = null;
            return capabilities as Map<String, Object?>;
          },
        }.entries) {
      test('${writer.key} omits null extensions', () {
        expect(writer.value().containsKey('extensions'), isFalse);
      });
    }

    for (final reader
        in {
          'client getter':
              () => (malformedCapabilities as ClientCapabilities).extensions,
          'server getter':
              () => (malformedCapabilities as ServerCapabilities).extensions,
        }.entries) {
      test('${reader.key} validates a cast capability map', () {
        expect(reader.value, throwsArgumentError);
      });
    }

    final implementation = Implementation(name: 'test', version: '1');
    final malformedClient = malformedCapabilities as ClientCapabilities;
    final malformedServer = malformedCapabilities as ServerCapabilities;
    for (final writer
        in <String, void Function()>{
          'initialize request': () {
            InitializeRequest(
              protocolVersion: ProtocolVersion.latestSupported,
              capabilities: malformedClient,
              clientInfo: implementation,
            );
          },
          'request envelope': () {
            MetaWithRequestEnvelope(
              protocolVersion: ProtocolVersion.latestSupported,
              capabilities: malformedClient,
            );
          },
          'initialize result': () {
            InitializeResult(
              protocolVersion: ProtocolVersion.latestSupported,
              serverCapabilities: malformedServer,
              serverInfo: implementation,
            );
          },
          'discover result': () {
            DiscoverResult(
              supportedVersions: const [],
              capabilities: malformedServer,
            );
          },
        }.entries) {
      test('${writer.key} validates capabilities before writing', () {
        expect(writer.value, throwsArgumentError);
      });
    }

    test('initialize request validates decoded client extensions', () {
      final request =
          <String, Object?>{'capabilities': malformedCapabilities}
              as InitializeRequest;

      expect(() => request.capabilities, throwsArgumentError);
    });

    test('initialize result validates decoded server extensions', () {
      final result = InitializeResult.fromMap({
        'capabilities': malformedCapabilities,
      });

      expect(() => result.capabilities, throwsArgumentError);
    });

    test('discover result validates decoded server extensions', () {
      final result = DiscoverResult.fromMap({
        'capabilities': malformedCapabilities,
      });

      expect(() => result.capabilities, throwsArgumentError);
    });

    test('client capabilities round trip an extensions map', () {
      final capabilities = ClientCapabilities(
        extensions: {
          'io.modelcontextprotocol/oauth-client-credentials': {},
          'com.example-tools.v2/n.a-b_c': {},
          'example/': {},
        },
      );

      final map = capabilities as Map<String, Object?>;
      expect(map['extensions'], {
        'io.modelcontextprotocol/oauth-client-credentials': <String, Object?>{},
        'com.example-tools.v2/n.a-b_c': <String, Object?>{},
        'example/': <String, Object?>{},
      });
      expect(capabilities.extensions, {
        'io.modelcontextprotocol/oauth-client-credentials': <String, Object?>{},
        'com.example-tools.v2/n.a-b_c': <String, Object?>{},
        'example/': <String, Object?>{},
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
