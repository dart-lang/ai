// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/server.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

import '../test_utils.dart';

/// These exercise [ServerConnection.discover] against a real [MCPServer]
/// instance connected over an in-memory [StreamChannel], instead of a
/// hand-written response queue: the [DiscoverResult] this test reads back
/// went through the same JSON-RPC encode/decode path a real connection uses,
/// so a field the client or server side gets wrong would show up here even
/// if it would not show up against a fake peer.
void main() {
  group('ServerConnection.discover against a real MCPServer', () {
    test('a real server\'s DiscoverResult round-trips and selects the '
        'newest mutually supported version', () async {
      final env = TestEnvironment(
        TestMCPClient(),
        (channel) => _DiscoverTestServer(
          channel,
          supportedVersions: const [
            '2024-11-05',
            '2026-07-28',
            // A version this package cannot know about yet: the server is
            // free to advertise one, and the client must not choke on it.
            '3000-01-01',
          ],
        ),
      );

      final result = await env.serverConnection.discover(
        protocolVersion: ProtocolVersion.v2026_07_28,
        capabilities: env.client.capabilities,
        clientInfo: env.client.implementation,
      );

      // The list came back exactly as the server sent it, through real
      // serialization, not a map literal a test wrote by hand.
      expect(result.supportedVersions, [
        '2024-11-05',
        '2026-07-28',
        '3000-01-01',
      ]);
      // The server's ServerCapabilities/Tools objects survived the trip.
      expect(result.capabilities.tools?.listChanged, isTrue);

      expect(
        ProtocolVersion.selectMutuallySupported(result.supportedVersions),
        ProtocolVersion.v2026_07_28,
      );
    });

    test('selectMutuallySupported returns null when a real server only '
        'advertises versions this client does not recognize', () async {
      final env = TestEnvironment(
        TestMCPClient(),
        (channel) => _DiscoverTestServer(
          channel,
          supportedVersions: const ['3000-01-01'],
        ),
      );

      final result = await env.serverConnection.discover(
        protocolVersion: ProtocolVersion.v2026_07_28,
        capabilities: env.client.capabilities,
      );

      expect(
        ProtocolVersion.selectMutuallySupported(result.supportedVersions),
        isNull,
      );
    });

    test('discover leaves a connection that never negotiated a legacy '
        'handshake exactly as unnegotiated', () async {
      final env = TestEnvironment(
        TestMCPClient(),
        (channel) => _DiscoverTestServer(channel, supportedVersions: const []),
      );

      await env.serverConnection.discover(
        protocolVersion: ProtocolVersion.v2026_07_28,
        capabilities: env.client.capabilities,
      );

      // Nothing here ever called initialize, so the late field the legacy
      // handshake would have set is still unset on this real connection.
      // (It throws a LateInitializationError, an Error and not a
      // StateError.)
      expect(() => env.serverConnection.protocolVersion, throwsA(isA<Error>()));
    });

    test('discover does not disturb the state a real legacy handshake '
        'already negotiated on the same connection', () async {
      final env = TestEnvironment(
        TestMCPClient(),
        (channel) => _DiscoverTestServer(
          channel,
          supportedVersions: const ['2026-07-28'],
        ),
      );
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

/// A real [MCPServer] which answers `server/discover` with a fixed list.
///
/// [MCPServer.discover] answers from what the server actually registered, so
/// it cannot name a version this package has no constant for. Registering the
/// handler here is what lets these tests hand the client a list containing
/// one.
base class _DiscoverTestServer extends MCPServer {
  _DiscoverTestServer(super.channel, {required this.supportedVersions})
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'discover test server',
          version: '2.0.0',
        ),
        instructions: 'A test server for ServerConnection.discover',
      ) {
    registerRequestHandler(DiscoverRequest.methodName, _handleDiscover);
  }

  /// The version strings this server hands back from `server/discover`.
  final List<String> supportedVersions;

  static final _capabilities = ServerCapabilities(
    tools: Tools(listChanged: true),
  );

  @override
  FutureOr<ServerCapabilities> initialize(MCPServerInitialization request) {
    super.initialize(request);
    return _capabilities;
  }

  FutureOr<DiscoverResult> _handleDiscover(DiscoverRequest _) => DiscoverResult(
    supportedVersions: supportedVersions,
    capabilities: _capabilities,
  );
}
