// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/src/utils/constants.dart';
import 'package:json_rpc_2/error_code.dart' as error_code;
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

import '../test_utils.dart';

void main() {
  group('ServerConnection.initializeAcrossVersions', () {
    test('settles on a modern server and reports what it discovered', () async {
      final harness = _Harness(
        (_, request) => handleRequestScopedMessage(
          request,
          _envelopeInitialization(request),
          TestMCPServer.new,
        ),
      );

      final result = await harness.connection.initializeAcrossVersions(
        _initialization(),
      );

      expect(result.protocolVersion, ProtocolVersion.v2026_07_28);
      expect(result.instructions, 'A test server');
      expect(result.serverInfo?.name, 'test server');
      expect(harness.connection.protocolVersion, ProtocolVersion.v2026_07_28);
      expect(harness.connection.serverInfo?.name, 'test server');
      // The modern branch sets this too. Reading it must not throw a
      // LateInitializationError.
      expect(harness.connection.serverCapabilities, same(result.capabilities));
    });

    test('hands its initialization fields to the server unchanged', () async {
      late _RecordingServer server;
      final harness = _Harness(
        (_, request) => handleRequestScopedMessage(
          request,
          _envelopeInitialization(request),
          (channel) => server = _RecordingServer(channel),
        ),
      );

      final initialization = MCPServerInitialization(
        protocolVersion: ProtocolVersion.v2026_07_28,
        clientCapabilities: ClientCapabilities(
          roots: RootsCapabilities(listChanged: true),
        ),
        clientInfo: Implementation(name: 'test client', version: '0.1.0'),
        logLevel: LoggingLevel.debug,
      );
      await harness.connection.initializeAcrossVersions(initialization);

      // The object a request-scoped transport built from the envelope carries
      // the same fields the caller handed the client.
      expect(
        server.lastInitialization!.protocolVersion,
        initialization.protocolVersion,
      );
      expect(
        server.lastInitialization!.clientCapabilities.roots?.listChanged,
        isTrue,
      );
      expect(
        server.lastInitialization!.clientInfo as Map<String, Object?>,
        equals(initialization.clientInfo as Map<String, Object?>),
      );
      expect(server.lastInitialization!.logLevel, LoggingLevel.debug);
    });

    test(
      'falls back to initialize on a legacy server and notifies it',
      () async {
        final environment = TestEnvironment(TestMCPClient(), TestMCPServer.new);

        final result = await environment.serverConnection
            .initializeAcrossVersions(_initialization());

        expect(result.protocolVersion, ProtocolVersion.latestSupported);
        expect(result.serverInfo?.name, 'test server');
        expect(result.instructions, 'A test server');
        expect(
          environment.serverConnection.protocolVersion,
          ProtocolVersion.latestSupported,
        );
        expect(
          environment.serverConnection.serverCapabilities,
          same(result.capabilities),
        );
        expect(environment.serverConnection.serverInfo?.name, 'test server');
        // The legacy handshake only completes once the server has received
        // the `notifications/initialized` notification this method sends
        // after a supported answer.
        await environment.server.initialized;
      },
    );

    test('skips the probe on a version without discover', () async {
      final harness = _Harness(_legacyAnswer);

      final result = await harness.connection.initializeAcrossVersions(
        _initialization(protocolVersion: ProtocolVersion.v2025_06_18),
      );

      expect(result.protocolVersion, ProtocolVersion.v2025_06_18);
      expect(
        harness.requests.map((request) => request[Keys.method]),
        isNot(contains(DiscoverRequest.methodName)),
      );
      // On the web compilers the `notifications/initialized` that follows can
      // already be recorded here. Pick the request out by its method.
      final initialize = harness.requests.singleWhere(
        (request) => request[Keys.method] == InitializeRequest.methodName,
      );
      expect(
        (initialize[Keys.params] as Map<String, Object?>)[Keys.protocolVersion],
        '2025-06-18',
      );
    });

    test('rethrows the modern refusals and does not fall back', () async {
      // The compatibility procedure stops on these codes. Any other error
      // falls back.
      for (final code in [
        McpErrorCodes.unsupportedProtocolVersion,
        McpErrorCodes.missingRequiredClientCapability,
        McpErrorCodes.headerMismatch,
      ]) {
        final harness = _Harness(
          (_, request) async => _errorResponse(request, code, 'refused'),
        );

        await expectLater(
          harness.connection.initializeAcrossVersions(_initialization()),
          throwsA(
            isA<RpcException>().having((error) => error.code, 'code', code),
          ),
        );
        expect(harness.requests, hasLength(1));
        expect(
          harness.requests.single[Keys.method],
          DiscoverRequest.methodName,
        );
      }
    });

    test('falls back after unrecognized RPC errors', () async {
      for (final code in [
        error_code.METHOD_NOT_FOUND,
        error_code.INVALID_PARAMS,
        // An application-defined error code.
        -32050,
      ]) {
        final harness = _Harness((harness, request) async {
          if (request[Keys.method] == DiscoverRequest.methodName) {
            return _errorResponse(request, code, 'not modern');
          }
          return _legacyAnswer(harness, request);
        });

        final result = await harness.connection.initializeAcrossVersions(
          _initialization(),
        );

        expect(result.protocolVersion, ProtocolVersion.latestSupported);
        expect(
          harness.requests.map((request) => request[Keys.method]),
          contains(InitializeRequest.methodName),
        );
      }
    });

    test('treats a server that stays silent as legacy', () async {
      final harness = _Harness((harness, request) async {
        if (request[Keys.method] == DiscoverRequest.methodName) {
          // Answer long after the probe was abandoned. The late answer must
          // not surface anywhere.
          await Future<void>.delayed(const Duration(milliseconds: 100));
          return _errorResponse(request, error_code.INTERNAL_ERROR, 'late');
        }
        return _legacyAnswer(harness, request);
      });

      final result = await harness.connection.initializeAcrossVersions(
        _initialization(),
        discoverTimeout: const Duration(milliseconds: 10),
      );

      expect(result.protocolVersion, ProtocolVersion.latestSupported);
      expect(
        harness.requests.map((request) => request[Keys.method]),
        contains(InitializeRequest.methodName),
      );
      // Wait for the abandoned probe's answer. If it surfaced as an unhandled
      // error this test would fail.
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });

    test(
      'throws when a legacy server settles on an unsupported version',
      () async {
        final harness = _Harness((_, request) async {
          if (request[Keys.method] == DiscoverRequest.methodName) {
            return _errorResponse(
              request,
              error_code.METHOD_NOT_FOUND,
              'Unknown method "server/discover".',
            );
          }
          return _resultResponse(request, {
            // Not a version this client knows. The initialize call has already
            // shut the connection down.
            Keys.protocolVersion: '1999-01-01',
            Keys.capabilities: <String, Object?>{},
            Keys.serverInfo: {'name': 'test server', 'version': '0.1.0'},
          });
        });

        await expectLater(
          harness.connection.initializeAcrossVersions(_initialization()),
          throwsStateError,
        );
        await harness.connection.done;
        expect(
          harness.requests.map((request) => request[Keys.method]),
          isNot(contains(InitializedNotification.methodName)),
        );
      },
    );

    test('reports the version a legacy server answers with', () async {
      final harness = _Harness((harness, request) async {
        if (request[Keys.method] == InitializeRequest.methodName) {
          return _resultResponse(request, {
            Keys.protocolVersion: ProtocolVersion.v2025_06_18.versionString,
            Keys.capabilities: <String, Object?>{},
            Keys.serverInfo: {'name': 'test server', 'version': '0.1.0'},
          });
        }
        return _legacyAnswer(harness, request);
      });

      final result = await harness.connection.initializeAcrossVersions(
        _initialization(protocolVersion: ProtocolVersion.latestSupported),
      );

      expect(result.protocolVersion, ProtocolVersion.v2025_06_18);
      expect(harness.connection.protocolVersion, ProtocolVersion.v2025_06_18);
      final initialize = harness.requests.singleWhere(
        (request) => request[Keys.method] == InitializeRequest.methodName,
      );
      final initializeParams = initialize[Keys.params] as Map<String, Object?>;
      expect(
        initializeParams[Keys.protocolVersion],
        ProtocolVersion.latestSupported.versionString,
      );
    });

    test('refuses a null clientInfo before sending anything', () async {
      final harness = _Harness(
        (_, request) async => _resultResponse(request, const {}),
      );

      await expectLater(
        harness.connection.initializeAcrossVersions(
          MCPServerInitialization(
            protocolVersion: ProtocolVersion.v2026_07_28,
            clientCapabilities: ClientCapabilities(),
          ),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.name,
            'name',
            'clientInfo',
          ),
        ),
      );
      expect(harness.requests, isEmpty);
    });

    test('throws when the answer does not list the probed version', () async {
      final harness = _Harness(
        (_, request) async => _resultResponse(request, {
          Keys.supportedVersions: ['2030-01-01'],
          Keys.capabilities: <String, Object?>{},
        }),
      );

      await expectLater(
        harness.connection.initializeAcrossVersions(_initialization()),
        throwsStateError,
      );
      expect(
        harness.requests.map((request) => request[Keys.method]),
        isNot(contains(InitializeRequest.methodName)),
      );
    });

    test('reports a null serverInfo when the answer leaves it out', () async {
      final harness = _Harness(
        (_, request) async => _resultResponse(request, {
          Keys.supportedVersions: ['2026-07-28'],
          Keys.capabilities: <String, Object?>{},
        }),
      );

      final result = await harness.connection.initializeAcrossVersions(
        _initialization(),
      );

      expect(result.protocolVersion, ProtocolVersion.v2026_07_28);
      expect(result.serverInfo, isNull);
      expect(harness.connection.serverInfo, isNull);
    });

    test('propagates a channel that closes during the probe', () async {
      final harness = _Harness((harness, request) async {
        harness.closeChannel();
        return null;
      });

      // A closed channel causes the pending probe to fail with a StateError,
      // without triggering fallback.
      await expectLater(
        harness.connection.initializeAcrossVersions(_initialization()),
        throwsStateError,
      );
      expect(
        harness.requests.map((request) => request[Keys.method]),
        isNot(contains(InitializeRequest.methodName)),
      );
    });

    test(
      'sends setLogLevel after a legacy answer that declared logging',
      () async {
        final harness = _Harness((_, request) async {
          if (request[Keys.method] == DiscoverRequest.methodName) {
            return _errorResponse(
              request,
              error_code.METHOD_NOT_FOUND,
              'Unknown method "server/discover".',
            );
          }
          if (request[Keys.method] == InitializeRequest.methodName) {
            final params = request[Keys.params] as Map<String, Object?>;
            return _resultResponse(request, {
              Keys.protocolVersion: params[Keys.protocolVersion],
              Keys.capabilities: {Keys.logging: <String, Object?>{}},
              Keys.serverInfo: {'name': 'test server', 'version': '0.1.0'},
            });
          }
          return _resultResponse(request, const {});
        });

        final result = await harness.connection.initializeAcrossVersions(
          _initialization(logLevel: LoggingLevel.debug),
        );

        expect(result.protocolVersion, ProtocolVersion.latestSupported);
        final setLevel = harness.requests.singleWhere(
          (request) => request[Keys.method] == SetLevelRequest.methodName,
        );
        expect(
          (setLevel[Keys.params] as Map<String, Object?>)[Keys.level],
          'debug',
        );
      },
    );

    test(
      'skips setLogLevel when the legacy answer declared no logging',
      () async {
        final harness = _Harness(_legacyAnswer);

        final result = await harness.connection.initializeAcrossVersions(
          _initialization(logLevel: LoggingLevel.debug),
        );

        expect(result.protocolVersion, ProtocolVersion.latestSupported);
        expect(
          harness.requests.map((request) => request[Keys.method]),
          isNot(contains(SetLevelRequest.methodName)),
        );
      },
    );

    test('keeps the handshake when setting the log level fails', () async {
      const errorCode = -32050;
      const serverCapabilities = {Keys.logging: <String, Object?>{}};
      final harness = _Harness((_, request) async {
        if (request[Keys.method] == DiscoverRequest.methodName) {
          return _errorResponse(
            request,
            error_code.METHOD_NOT_FOUND,
            'Unknown method "server/discover".',
          );
        }
        if (request[Keys.method] == InitializeRequest.methodName) {
          final params = request[Keys.params] as Map<String, Object?>;
          return _resultResponse(request, {
            Keys.protocolVersion: params[Keys.protocolVersion],
            Keys.capabilities: serverCapabilities,
            Keys.serverInfo: {'name': 'test server', 'version': '0.1.0'},
          });
        }
        if (request[Keys.method] == SetLevelRequest.methodName) {
          return _errorResponse(request, errorCode, 'log level refused');
        }
        return _resultResponse(request, const {});
      });

      await expectLater(
        harness.connection.initializeAcrossVersions(
          _initialization(logLevel: LoggingLevel.debug),
        ),
        throwsA(
          isA<RpcException>().having((error) => error.code, 'code', errorCode),
        ),
      );

      final methods =
          harness.requests.map((request) => request[Keys.method]).toList();
      expect(
        methods,
        containsAll([
          InitializedNotification.methodName,
          SetLevelRequest.methodName,
        ]),
      );
      expect(
        methods.indexOf(InitializedNotification.methodName),
        lessThan(methods.indexOf(SetLevelRequest.methodName)),
      );
      expect(
        harness.connection.protocolVersion,
        ProtocolVersion.latestSupported,
      );
      expect(
        harness.connection.serverCapabilities as Map<String, Object?>,
        equals(serverCapabilities),
      );
      expect(harness.connection.serverInfo?.name, 'test server');
      expect(harness.connection.serverInfo?.version, '0.1.0');
    });
  });
}

/// The initialization most tests offer, on the newest revision this package
/// knows.
MCPServerInitialization _initialization({
  ProtocolVersion protocolVersion = ProtocolVersion.v2026_07_28,
  LoggingLevel? logLevel,
}) => MCPServerInitialization(
  protocolVersion: protocolVersion,
  clientCapabilities: ClientCapabilities(),
  clientInfo: Implementation(name: 'test client', version: '0.1.0'),
  logLevel: logLevel,
);

/// Reads initialization fields from the request envelope.
MCPServerInitialization _envelopeInitialization(Map<String, Object?> request) {
  final params = request[Keys.params];
  final meta = params is Map<String, Object?> ? params[Keys.meta] : null;
  if (meta is! Map<String, Object?>) fail('No envelope on $request');

  final version = ProtocolVersion.tryParse('${meta[Keys.protocolVersionMeta]}');
  if (version == null) fail('No protocol version in the envelope $meta');
  final capabilities = meta[Keys.clientCapabilitiesMeta];
  if (capabilities is! Map<String, Object?>) {
    fail('No client capabilities in the envelope $meta');
  }
  final clientInfo = meta[Keys.clientInfoMeta] as Map<String, Object?>?;
  final logLevelName = meta[Keys.logLevelMeta];

  return MCPServerInitialization(
    protocolVersion: version,
    clientCapabilities: ClientCapabilities.fromMap(capabilities),
    clientInfo: clientInfo == null ? null : Implementation.fromMap(clientInfo),
    logLevel:
        logLevelName is String
            ? LoggingLevel.values.firstWhere(
              (level) => level.name == logLevelName,
            )
            : null,
  );
}

/// Answers as a server from before 2026-07-28 would. The probe gets the error
/// json_rpc_2 picks for an unknown method, and `initialize` echoes the
/// requested version back.
Future<Map<String, Object?>?> _legacyAnswer(
  _Harness harness,
  Map<String, Object?> request,
) async {
  if (request[Keys.method] == DiscoverRequest.methodName) {
    return _errorResponse(
      request,
      error_code.METHOD_NOT_FOUND,
      'Unknown method "server/discover".',
    );
  }
  if (request[Keys.method] == InitializeRequest.methodName) {
    final params = request[Keys.params] as Map<String, Object?>;
    return _resultResponse(request, {
      Keys.protocolVersion: params[Keys.protocolVersion],
      Keys.capabilities: <String, Object?>{},
      Keys.serverInfo: {'name': 'test server', 'version': '0.1.0'},
      Keys.instructions: 'A test server',
    });
  }
  return _resultResponse(request, const {});
}

/// A successful response carrying [result] for [request].
Map<String, Object?> _resultResponse(
  Map<String, Object?> request,
  Map<String, Object?> result,
) => {Keys.jsonrpc: '2.0', Keys.id: request[Keys.id], Keys.result: result};

/// An error response carrying [code] and [message] for [request].
Map<String, Object?> _errorResponse(
  Map<String, Object?> request,
  int code,
  String message,
) => {
  Keys.jsonrpc: '2.0',
  Keys.id: request[Keys.id],
  Keys.error: {Keys.code: code, Keys.message: message},
};

/// Drives a [ServerConnection] over an in-memory channel.
///
/// Each request is recorded and passed to [_respond]. A `null` result sends
/// no answer. A delayed answer still goes out after the connection stops
/// waiting.
class _Harness {
  _Harness(this._respond) {
    addTearDown(_incoming.close);
    addTearDown(client.shutdown);
    connection = client.connectServer(
      StreamChannel.withGuarantees(_incoming.stream, _outgoing.sink),
    );
    _outgoing.stream.listen((request) async {
      requests.add(request);
      final answer = await _respond(this, request);
      if (answer != null && !_incoming.isClosed) _incoming.add(answer);
    });
  }

  final Future<Map<String, Object?>?> Function(
    _Harness harness,
    Map<String, Object?> request,
  )
  _respond;
  final client = TestMCPClient();
  final _incoming = StreamController<Map<String, Object?>>();
  final _outgoing = StreamController<Map<String, Object?>>();

  /// The requests the connection has sent.
  final requests = <Map<String, Object?>>[];

  late final ServerConnection connection;

  /// Ends what the connection reads, as a server that exits does.
  void closeChannel() => _incoming.close();
}

/// A [TestMCPServer] that records the [MCPServerInitialization] its
/// [initialize] was given.
base class _RecordingServer extends TestMCPServer {
  _RecordingServer(super.channel);

  MCPServerInitialization? lastInitialization;

  @override
  FutureOr<void> initialize(MCPServerInitialization initialization) {
    lastInitialization = initialization;
    return super.initialize(initialization);
  }
}
