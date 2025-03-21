// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:meta/meta.dart';
import 'package:stream_channel/stream_channel.dart';

import '../api.dart';
import '../util.dart';

/// Base class to extend when implementing an MCP server.
///
/// Actual functionality beyond server initialization is done by mixing in
/// additional support mixins such as [ToolsSupport] etc.
abstract class MCPServer {
  /// Whether or not this server has finished initialization and gotten the
  /// final ack from the client.
  bool initialized = false;

  final Peer _peer;

  ServerImplementation get implementation;

  MCPServer.fromStreamChannel(StreamChannel<String> channel)
    : _peer = Peer(channel) {
    _peer.registerMethod(
      InitializeRequest.methodName,
      convertParameters(initialize),
    );
    var x = convertParameters(handleInitialized);
    _peer.registerMethod(InitializedNotification.methodName, x);

    _peer.listen();
  }

  @mustCallSuper
  /// Mixins should register their methods in this method, as well as editing
  /// the [InitializeResult.capabilities] as needed.
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    assert(!initialized);
    return InitializeResult(
      protocolVersion: protocolVersion,
      serverCapabilities: ServerCapabilities(),
      serverInfo: implementation,
    );
  }

  /// Called by the client after accepting our [InitializeResult].
  ///
  /// The server should not respond.
  @mustCallSuper
  Null handleInitialized(InitializedNotification notification) {
    initialized = true;
  }
}

/// A mixin for MCP servers which support the `tools` capability.
mixin ToolsSupport on MCPServer {
  /// Whether or not this server supports sending notifications about the list
  /// of tools changing.
  ///
  /// This should only be overridden to provide the value `true`, otherwise
  /// different mixins could step on each others toes.
  bool get supportsListChanged => false;

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) async {
    _peer.registerMethod(
      ListToolsRequest.methodName,
      convertParameters(listTools),
    );

    _peer.registerMethod(
      CallToolRequest.methodName,
      convertParameters(callTool),
    );
    var result = await super.initialize(request);
    (result.capabilities.tools ??= Tools()).listChanged = supportsListChanged;
    return result;
  }

  /// Returns the list of supported tools for this server.
  FutureOr<ListToolsResult> listTools(ListToolsRequest request);

  /// Invoked when one of the tools from [listTools] is called.
  FutureOr<CallToolResult> callTool(CallToolRequest request);
}
