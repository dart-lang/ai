// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/src/utils/constants.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

import '../test_utils.dart';

void main() {
  group('ServerConnection.discover', () {
    test('sends the metadata the 2026-07-28 envelope requires', () async {
      final harness = _WireHarness.answering(_answer);

      await harness.connection.discover(
        protocolVersion: ProtocolVersion.v2026_07_28,
        capabilities: ClientCapabilities(
          elicitation: ElicitationCapability(form: {}),
        ),
        clientInfo: Implementation(name: 'test client', version: '0.1.0'),
      );

      // The reserved keys are spelled out here, since the point of this test
      // is that they match the specification and not our own constants.
      expect(harness.requests.single[Keys.method], 'server/discover');
      expect(harness.metadata, {
        'io.modelcontextprotocol/protocolVersion': '2026-07-28',
        'io.modelcontextprotocol/clientInfo': {
          'name': 'test client',
          'version': '0.1.0',
        },
        'io.modelcontextprotocol/clientCapabilities': {
          'elicitation': {'form': <String, Object?>{}},
        },
      });
    });

    test(
      'leaves clientInfo out of the envelope when it is not given',
      () async {
        final harness = _WireHarness.answering(_answer);

        await harness.connection.discover(
          protocolVersion: ProtocolVersion.v2026_07_28,
          capabilities: ClientCapabilities(),
        );

        final meta = harness.metadata;
        expect(meta, isNot(contains(Keys.clientInfoMeta)));
        expect(meta[Keys.protocolVersionMeta], '2026-07-28');
        expect(meta[Keys.clientCapabilitiesMeta], isEmpty);
      },
    );

    test('keeps caller metadata and overwrites the keys it writes', () async {
      final harness = _WireHarness.answering(_answer);

      await harness.connection.discover(
        protocolVersion: ProtocolVersion.v2025_11_25,
        capabilities: ClientCapabilities(
          elicitation: ElicitationCapability(form: {}),
        ),
        clientInfo: Implementation(name: 'test client', version: '0.1.0'),
        meta: MetaWithProgressToken.fromMap({
          Keys.progressToken: 'token-1',
          'example.com/custom': 'kept',
          // The three reserved keys, set to values the method must replace
          // with the ones it was given.
          Keys.protocolVersionMeta: '1900-01-01',
          Keys.clientCapabilitiesMeta: {Keys.sampling: <String, Object?>{}},
          Keys.clientInfoMeta: {
            Keys.name: 'spoofed client',
            Keys.version: '9.9.9',
          },
        }),
      );

      final meta = harness.metadata;
      expect(meta[Keys.progressToken], 'token-1');
      expect(meta['example.com/custom'], 'kept');
      expect(meta[Keys.protocolVersionMeta], '2025-11-25');
      expect(meta[Keys.clientCapabilitiesMeta], {
        Keys.elicitation: {Keys.form: <String, Object?>{}},
      });
      expect(meta[Keys.clientInfoMeta], {
        Keys.name: 'test client',
        Keys.version: '0.1.0',
      });
    });

    test('leaves a caller client info key alone when none is given', () async {
      final harness = _WireHarness.answering(_answer);

      await harness.connection.discover(
        protocolVersion: ProtocolVersion.v2026_07_28,
        capabilities: ClientCapabilities(),
        meta: MetaWithProgressToken.fromMap({
          Keys.clientInfoMeta: {Keys.name: 'spoofed', Keys.version: '9.9.9'},
        }),
      );

      expect(harness.metadata[Keys.clientInfoMeta], {
        Keys.name: 'spoofed',
        Keys.version: '9.9.9',
      });
    });

    test('reads a server answer without taking over the connection', () async {
      final harness = _WireHarness.dispatching();

      final result = await harness.connection.discover(
        protocolVersion: ProtocolVersion.v2026_07_28,
        capabilities: ClientCapabilities(),
        clientInfo: Implementation(name: 'test client', version: '0.1.0'),
      );

      expect(result.supportedVersions, ['2026-07-28']);
      expect(result.instructions, 'A test server');
      expect(harness.connection.serverInfo, isNull);
    });
  });
}

/// A well-formed answer for the tests that only look at the request.
const _answer = <String, Object?>{
  'supportedVersions': ['2026-07-28'],
  'capabilities': <String, Object?>{},
};

/// Drives a [ServerConnection] over an in-memory channel, recording the
/// requests it sends and answering each one with `_respond`.
class _WireHarness {
  _WireHarness(this._respond) {
    final client = TestMCPClient();
    addTearDown(client.shutdown);
    addTearDown(_incoming.close);
    connection = client.connectServer(
      StreamChannel.withGuarantees(_incoming.stream, _outgoing.sink),
    );
    _outgoing.stream.listen((request) async {
      requests.add(request);
      _incoming.add({
        Keys.jsonrpc: '2.0',
        Keys.id: request[Keys.id],
        Keys.result: await _respond(request),
      });
    });
  }

  /// Answers every request with [result], for tests about what was sent.
  _WireHarness.answering(Map<String, Object?> result)
    : this((_) async => result);

  /// Answers with a real [TestMCPServer], reached the way a request-scoped
  /// transport reaches one.
  ///
  /// The per-request context comes from the `_meta` the client wrote, so a
  /// request that does not carry it cannot be served.
  _WireHarness.dispatching() : this(_dispatch);

  final Future<Map<String, Object?>> Function(Map<String, Object?> request)
  _respond;
  final _incoming = StreamController<Map<String, Object?>>();
  final _outgoing = StreamController<Map<String, Object?>>();

  /// The requests the connection has sent.
  final requests = <Map<String, Object?>>[];

  late final ServerConnection connection;

  /// The `_meta` envelope on the one request that was sent.
  Map<String, Object?> get metadata =>
      (requests.single[Keys.params] as Map<String, Object?>)[Keys.meta]
          as Map<String, Object?>;
}

Future<Map<String, Object?>> _dispatch(Map<String, Object?> request) async {
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

  final response = await handleRequestScopedMessage(
    request,
    MCPServerInitialization(
      protocolVersion: version,
      clientCapabilities: ClientCapabilities.fromMap(capabilities),
      clientInfo:
          clientInfo == null ? null : Implementation.fromMap(clientInfo),
    ),
    TestMCPServer.new,
  );
  final result = response?[Keys.result];
  if (result is! Map<String, Object?>) fail('The server answered $response');
  return result;
}
