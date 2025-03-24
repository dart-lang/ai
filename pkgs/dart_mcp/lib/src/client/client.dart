// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
// TODO: Refactor to drop this dependency?
import 'dart:io';

import 'package:async/async.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:stream_channel/stream_channel.dart';

import '../api.dart';

abstract class MCPClient {
  ClientCapabilities get capabilities;
  ClientImplementation get implementation;

  final Map<String, ServerConnection> _connections = {};

  /// Connect to a new MCP server with [name], by invoking [command] with
  /// [arguments] and talking to that process over stdin/stdout.
  Future<ServerConnection> connectStdioServer(
    String name,
    String command,
    List<String> arguments,
  ) async {
    var process = await Process.start(command, arguments);
    var channel = StreamChannel.withCloseGuarantee(
          process.stdout,
          process.stdin,
        )
        .transform(StreamChannelTransformer.fromCodec(utf8))
        .transformStream(const LineSplitter())
        .transformSink(
          StreamSinkTransformer.fromHandlers(
            handleData: (data, sink) {
              sink.add('$data\n');
            },
          ),
        );
    return connectServer(name, channel);
  }

  /// Returns a connection for an MCP server with [name], communicating over
  /// [channel], which is already established.
  ServerConnection connectServer(String name, StreamChannel<String> channel) {
    var connection = ServerConnection.fromStreamChannel(channel);
    _connections[name] = connection;
    return connection;
  }

  Future<void> shutdownServer(String name) {
    var server = _connections.remove(name);
    if (server == null) {
      throw ArgumentError('No server with name $name');
    }
    return server.shutdown();
  }
}

/// An active server connection.
class ServerConnection {
  final Peer _peer;

  ServerConnection.fromStreamChannel(StreamChannel<String> channel)
    : _peer = Peer(channel) {
    _peer.listen();
  }

  Future<void> shutdown() => _peer.close();

  /// Called after a successful call to [initialize].
  void notifyInitialized(InitializedNotification notification) {
    _peer.sendNotification(InitializedNotification.methodName, notification);
  }

  /// Initializes the server, this should be done before anything else.
  ///
  /// The client must call [notifyInitialized] after receiving and accepting
  /// this response.
  Future<InitializeResult> initialize(InitializeRequest request) async {
    return InitializeResult.fromMap(
      ((await _peer.sendRequest(InitializeRequest.methodName, request)) as Map)
          .cast(),
    );
  }

  /// List all the tools from this server.
  Future<ListToolsResult> listTools() async {
    return ListToolsResult.fromMap(
      ((await _peer.sendRequest(
                ListToolsRequest.methodName,
                ListToolsRequest(),
              ))
              as Map)
          .cast(),
    );
  }

  /// Invokes a [Tool] returned from the [ListToolsResult].
  Future<CallToolResult> callTool(CallToolRequest request) async {
    return CallToolResult.fromMap(
      ((await _peer.sendRequest(CallToolRequest.methodName, request)) as Map)
          .cast(),
    );
  }
}
