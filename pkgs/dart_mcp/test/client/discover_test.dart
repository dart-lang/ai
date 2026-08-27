// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/src/utils/constants.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

import '../test_utils.dart';

void main() {
  group('ServerConnection.discover', () {
    test('sends the metadata the 2026-07-28 envelope requires', () async {
      final harness = _WireHarness();
      harness.respondToNextRequest({
        Keys.resultType: ResultTypes.complete,
        Keys.ttlMs: 0,
        Keys.cacheScope: CacheScope.private.name,
        Keys.supportedVersions: ['2026-07-28'],
        Keys.capabilities: {Keys.tools: <String, Object?>{}},
      });

      final result = await harness.connection.discover(
        protocolVersion: ProtocolVersion.v2026_07_28,
        capabilities: ClientCapabilities(
          elicitation: ElicitationCapability(form: {}),
        ),
        clientInfo: Implementation(name: 'test client', version: '0.1.0'),
      );

      final request = harness.requests.single;
      expect(request['method'], 'server/discover');
      final meta = (request['params'] as Map)['_meta'] as Map<String, Object?>;
      expect(meta, {
        'io.modelcontextprotocol/protocolVersion': '2026-07-28',
        'io.modelcontextprotocol/clientInfo': {
          'name': 'test client',
          'version': '0.1.0',
        },
        'io.modelcontextprotocol/clientCapabilities': {
          'elicitation': {'form': <String, Object?>{}},
        },
      });

      expect(result.supportedVersions, ['2026-07-28']);
      expect(result.capabilities.tools, isNotNull);
    });

    test(
      'leaves clientInfo out of the envelope when it is not given',
      () async {
        final harness = _WireHarness();
        harness.respondToNextRequest({
          Keys.resultType: ResultTypes.complete,
          Keys.ttlMs: 0,
          Keys.cacheScope: CacheScope.private.name,
          Keys.supportedVersions: ['2026-07-28'],
          Keys.capabilities: <String, Object?>{},
        });

        await harness.connection.discover(
          protocolVersion: ProtocolVersion.v2026_07_28,
          capabilities: ClientCapabilities(),
        );

        final meta =
            (harness.requests.single[Keys.params] as Map)[Keys.meta]
                as Map<String, Object?>;
        expect(meta, isNot(contains(Keys.clientInfoMeta)));
        expect(meta[Keys.protocolVersionMeta], '2026-07-28');
        expect(meta[Keys.clientCapabilitiesMeta], isEmpty);
      },
    );

    test('keeps caller metadata and overwrites the keys it writes', () async {
      final harness = _WireHarness();
      harness.respondToNextRequest({
        Keys.resultType: ResultTypes.complete,
        Keys.ttlMs: 0,
        Keys.cacheScope: CacheScope.private.name,
        Keys.supportedVersions: ['2026-07-28'],
        Keys.capabilities: <String, Object?>{},
      });

      await harness.connection.discover(
        protocolVersion: ProtocolVersion.v2026_07_28,
        capabilities: ClientCapabilities(
          elicitation: ElicitationCapability(form: {}),
        ),
        clientInfo: Implementation(name: 'test client', version: '0.1.0'),
        meta: MetaWithProgressToken.fromMap({
          Keys.progressToken: 'token-1',
          'example.com/custom': 'kept',
          // The three reserved keys, set to values the method must replace.
          Keys.protocolVersionMeta: '1900-01-01',
          Keys.clientCapabilitiesMeta: {Keys.sampling: <String, Object?>{}},
          Keys.clientInfoMeta: {
            Keys.name: 'spoofed client',
            Keys.version: '9.9.9',
          },
        }),
      );

      final meta =
          (harness.requests.single[Keys.params] as Map)[Keys.meta]
              as Map<String, Object?>;
      expect(meta[Keys.progressToken], 'token-1');
      expect(meta['example.com/custom'], 'kept');
      expect(meta[Keys.protocolVersionMeta], '2026-07-28');
      expect(meta[Keys.clientCapabilitiesMeta], {
        Keys.elicitation: {Keys.form: <String, Object?>{}},
      });
      expect(meta[Keys.clientInfoMeta], {
        Keys.name: 'test client',
        Keys.version: '0.1.0',
      });
    });

    test('leaves a caller client info key alone when none is given', () async {
      final harness = _WireHarness();
      harness.respondToNextRequest({
        Keys.resultType: ResultTypes.complete,
        Keys.ttlMs: 0,
        Keys.cacheScope: CacheScope.private.name,
        Keys.supportedVersions: ['2026-07-28'],
        Keys.capabilities: <String, Object?>{},
      });

      await harness.connection.discover(
        protocolVersion: ProtocolVersion.v2026_07_28,
        capabilities: ClientCapabilities(),
        meta: MetaWithProgressToken.fromMap({
          Keys.clientInfoMeta: {Keys.name: 'spoofed', Keys.version: '9.9.9'},
        }),
      );

      final meta =
          (harness.requests.single[Keys.params] as Map)[Keys.meta]
              as Map<String, Object?>;
      expect(meta[Keys.clientInfoMeta], {
        Keys.name: 'spoofed',
        Keys.version: '9.9.9',
      });
    });

    test('does not touch the connection state a handshake would set', () async {
      final harness = _WireHarness();
      harness.respondToNextRequest({
        Keys.protocolVersion: ProtocolVersion.v2025_11_25.versionString,
        Keys.capabilities: {Keys.tools: <String, Object?>{}},
        Keys.serverInfo: {
          Keys.name: 'negotiated server',
          Keys.version: '1.0.0',
        },
      });
      await harness.connection.initialize(
        InitializeRequest(
          protocolVersion: ProtocolVersion.v2025_11_25,
          capabilities: ClientCapabilities(),
          clientInfo: Implementation(name: 'test client', version: '0.1.0'),
        ),
      );

      harness.respondToNextRequest({
        Keys.resultType: ResultTypes.complete,
        Keys.ttlMs: 0,
        Keys.cacheScope: CacheScope.private.name,
        Keys.supportedVersions: ['2026-07-28'],
        Keys.capabilities: {Keys.prompts: <String, Object?>{}},
      });
      final result = await harness.connection.discover(
        protocolVersion: ProtocolVersion.v2026_07_28,
        capabilities: ClientCapabilities(),
      );

      // The result carries what the server just said.
      expect(result.supportedVersions, ['2026-07-28']);
      expect(result.capabilities.prompts, isNotNull);

      // The connection still carries what the handshake settled on.
      expect(harness.connection.protocolVersion, ProtocolVersion.v2025_11_25);
      expect(harness.connection.serverCapabilities.tools, isNotNull);
      expect(harness.connection.serverCapabilities.prompts, isNull);
      expect(harness.connection.serverInfo?.name, 'negotiated server');
    });
  });
}

/// A client whose peer is this test: requests surface in [requests] and are
/// answered with whatever the test queued.
///
/// Reading the request off the wire is what these tests are about, so the peer
/// is the test itself. `discover_server_test.dart` covers the same call
/// against a real server.
class _WireHarness {
  final incoming = StreamController<Map<String, Object?>>();
  final outgoing = StreamController<Map<String, Object?>>();
  final requests = <Map<String, Object?>>[];
  final _responses = <Map<String, Object?>>[];

  late final ServerConnection connection;

  _WireHarness() {
    final client = TestMCPClient();
    addTearDown(client.shutdown);
    connection = client.connectServer(
      StreamChannel.withGuarantees(incoming.stream, outgoing.sink),
    );
    outgoing.stream.listen((request) {
      requests.add(request);
      incoming.add({
        Keys.jsonrpc: '2.0',
        Keys.id: request[Keys.id],
        Keys.result: _responses.removeAt(0),
      });
    });
  }

  /// Queues [result] as the response to the next request.
  void respondToNextRequest(Map<String, Object?> result) =>
      _responses.add(result);
}
