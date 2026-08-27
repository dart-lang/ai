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
      final harness = _WireHarness();
      harness.respondToNextRequest(_completeResult(tools: {}));

      await harness.connection.discover(
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
    });

    test(
      'leaves clientInfo out of the envelope when it is not given',
      () async {
        final harness = _WireHarness();
        harness.respondToNextRequest(_completeResult());

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
      final harness = _WireHarness();
      harness.respondToNextRequest(_completeResult());

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

      final meta = harness.metadata;
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
      harness.respondToNextRequest(_completeResult());

      await harness.connection.discover(
        protocolVersion: ProtocolVersion.v2026_07_28,
        capabilities: ClientCapabilities(),
        meta: MetaWithProgressToken.fromMap({
          Keys.clientInfoMeta: {Keys.name: 'spoofed', Keys.version: '9.9.9'},
        }),
      );

      final meta = harness.metadata;
      expect(meta[Keys.clientInfoMeta], {
        Keys.name: 'spoofed',
        Keys.version: '9.9.9',
      });
    });

    test(
      'returns a real server result without changing handshake state',
      () async {
        final env = TestEnvironment(TestMCPClient(), _DiscoverTestServer.new);
        await env.initializeServer(
          protocolVersion: ProtocolVersion.v2025_11_25,
        );

        final result = await env.serverConnection.discover(
          protocolVersion: ProtocolVersion.v2026_07_28,
          capabilities: env.client.capabilities,
          clientInfo: env.client.implementation,
        );

        expect(result as Map<String, Object?>, {
          'cacheScope': 'private',
          'capabilities': {
            'tools': {'listChanged': true},
          },
          'resultType': 'complete',
          'supportedVersions': ['2026-07-28'],
          'ttlMs': 0,
        });
        expect(
          env.serverConnection.protocolVersion,
          ProtocolVersion.v2025_11_25,
        );
      },
    );
  });
}

Map<String, Object?> _completeResult({Map<String, Object?>? tools}) => {
  'cacheScope': 'private',
  'capabilities': {if (tools != null) 'tools': tools},
  'resultType': 'complete',
  'supportedVersions': ['2026-07-28'],
  'ttlMs': 0,
};

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

  Map<String, Object?> get metadata =>
      (requests.single['params'] as Map)['_meta'] as Map<String, Object?>;

  void respondToNextRequest(Map<String, Object?> result) =>
      _responses.add(result);
}

base class _DiscoverTestServer extends MCPServer {
  _DiscoverTestServer(super.channel)
    : super.fromStreamChannel(
        implementation: Implementation(name: 'server', version: '2.0.0'),
        instructions: 'test server',
      ) {
    registerRequestHandler(DiscoverRequest.methodName, _handleDiscover);
  }

  static final _capabilities = ServerCapabilities(
    tools: Tools(listChanged: true),
  );

  @override
  FutureOr<ServerCapabilities> initialize(MCPServerInitialization request) {
    super.initialize(request);
    return _capabilities;
  }

  FutureOr<DiscoverResult> _handleDiscover(DiscoverRequest _) =>
      DiscoverResult.fromMap(_completeResult(tools: {'listChanged': true}));
}
