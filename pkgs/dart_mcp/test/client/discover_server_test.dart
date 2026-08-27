// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/src/utils/constants.dart';
import 'package:test/test.dart';

import '../test_utils.dart';

/// Exercises [ServerConnection.discover] against an [MCPServer] connected over
/// an in-memory decoded-message channel. The result passes through the same
/// JSON-RPC validation and dispatch path as other stream-channel connections.
void main() {
  group('ServerConnection.discover against a real MCPServer', () {
    test('a real server returns every required DiscoverResult field', () async {
      final env = TestEnvironment(TestMCPClient(), _DiscoverTestServer.new);

      final result = await env.serverConnection.discover(
        protocolVersion: ProtocolVersion.v2026_07_28,
        capabilities: env.client.capabilities,
        clientInfo: env.client.implementation,
      );

      expect(result.supportedVersions, ['2026-07-28']);
      expect(result.capabilities.tools?.listChanged, isTrue);
      final resultMap = result as Map<String, Object?>;
      expect(resultMap.keys, {
        'cacheScope',
        'capabilities',
        'resultType',
        'supportedVersions',
        'ttlMs',
      });
      expect(resultMap, containsPair('ttlMs', 0));
      expect(resultMap, containsPair('cacheScope', CacheScope.private.name));
      expect(resultMap, containsPair('resultType', ResultTypes.complete));
    });

    test('discover does not disturb the state a real legacy handshake '
        'already negotiated on the same connection', () async {
      final env = TestEnvironment(TestMCPClient(), _DiscoverTestServer.new);
      await env.initializeServer(protocolVersion: ProtocolVersion.v2025_11_25);
      expect(env.serverConnection.protocolVersion, ProtocolVersion.v2025_11_25);

      await env.serverConnection.discover(
        protocolVersion: ProtocolVersion.v2026_07_28,
        capabilities: env.client.capabilities,
      );

      // The handshake's negotiated version is exactly what a discover call
      // on the same connection must leave alone.
      expect(env.serverConnection.protocolVersion, ProtocolVersion.v2025_11_25);
    });
  });
}

base class _DiscoverTestServer extends MCPServer {
  _DiscoverTestServer(super.channel)
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'discover test server',
          version: '2.0.0',
        ),
        instructions: 'A test server for ServerConnection.discover',
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
      DiscoverResult.fromMap({
        Keys.resultType: ResultTypes.complete,
        Keys.ttlMs: 0,
        Keys.cacheScope: CacheScope.private.name,
        Keys.supportedVersions: ['2026-07-28'],
        Keys.capabilities: _capabilities,
      });
}
