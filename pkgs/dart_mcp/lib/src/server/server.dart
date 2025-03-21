// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:meta/meta.dart';
import 'package:stream_channel/stream_channel.dart';

import '../api.dart';

abstract class MCPServer {
  final Peer _peer;
  ServerCapabilities get capabilities;
  ServerImplementation get implementation;

  MCPServer.fromStreamChannel(StreamChannel<String> channel)
    : _peer = Peer(channel) {
    _peer.registerMethod('initialize', initialize);
    _peer.listen();
  }

  @mustCallSuper
  InitializeResult initialize(InitializeRequest request) {
    return InitializeResult(
      protocolVersion: protocolVersion,
      ServerCapabilities: capabilities,
      serverInfo: implementation,
    );
  }
}

/// A mixin for MCP servers which support the `tools` capability.
mixin ToolsSupport on MCPServer {
  @override
  InitializeResult initialize(InitializeRequest request) {
    _peer.registerMethod(ListToolsRequest.methodName, listTools);
    return super.initialize(request);
  }

  /// Must be implemented by the server.
  ListToolsResult listTools(ListToolsRequest request);
}
