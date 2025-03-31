// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/server.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

class TestEnvironment<Client extends MCPClient, Server extends MCPServer> {
  /// The client side of the communication channel - the stream is the incoming
  /// data and the sink is outgoing data.
  final clientController = StreamController<String>();

  /// The server side of the communication channel - the stream is the incoming
  /// data and the sink is outgoing data.
  final serverController = StreamController<String>();

  late final clientChannel = StreamChannel<String>.withCloseGuarantee(
    serverController.stream,
    clientController.sink,
  );
  late final serverChannel = StreamChannel<String>.withCloseGuarantee(
    clientController.stream,
    serverController.sink,
  );

  final Client client;
  late final Server server;
  late final ServerConnection serverConnection;

  /// Creates a [TestEnvironment], and adds a [tearDown] to shut it down
  /// automatically.
  ///
  /// You may manually shut down the environment by calling [shutdown].
  TestEnvironment(
    this.client,
    Server Function(StreamChannel<String>) createServer,
  ) {
    server = createServer(serverChannel);
    serverConnection = client.connectServer(
      server.implementation.name,
      clientChannel,
    );
    addTearDown(shutdown);
  }

  /// Initializes the server and waits for it to receive the initialization
  /// notification, then returns the original [InitializeResult] for tests
  /// to inspect if desired.
  Future<InitializeResult> initializeServer() async {
    var initializeResult = await serverConnection.initialize(
      InitializeRequest(
        protocolVersion: protocolVersion,
        capabilities: client.capabilities,
        clientInfo: client.implementation,
      ),
    );
    serverConnection.notifyInitialized(InitializedNotification());
    await server.initialized;
    return initializeResult;
  }

  Future<void> shutdown() async {
    await client.shutdown();
    await server.shutdown();
  }
}

base class TestMCPClient extends MCPClient {
  TestMCPClient()
    : super(ClientImplementation(name: 'test client', version: '0.1.0'));
}

base class TestMCPServer extends MCPServer {
  @override
  final ServerImplementation implementation = ServerImplementation(
    name: 'test server',
    version: '0.1.0',
  );

  @override
  final instructions = 'A test server';

  TestMCPServer(super.channel) : super.fromStreamChannel();
}
