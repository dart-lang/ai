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
  /// Completes when this server has finished initialization and gotten the
  /// final ack from the client.
  FutureOr<void> get initialized => _initialized.future;
  final Completer<void> _initialized = Completer<void>();

  /// Whether this server is still active and has completed initialization.
  bool get ready => !_peer.isClosed && _initialized.isCompleted;

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
    assert(!_initialized.isCompleted);
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
  void handleInitialized(InitializedNotification notification) {
    _initialized.complete();
  }
}

/// A mixin for MCP servers which support the `tools` capability.
///
/// Servers should register tools using the [registerTool] method, typically
/// inside the [initialize] method, but they may also be registered after
/// initialization if needed.
mixin ToolsSupport on MCPServer {
  /// The registered tools by name.
  final Map<String, Tool> _registeredTools = {};

  /// The registered tool implementations by name.
  final Map<String, FutureOr<CallToolResult> Function(CallToolRequest)>
  _registeredToolImpls = {};

  /// Invoked by the client as a part of initialization.
  ///
  /// Tools should usually be registered in this function using [registerTool]
  /// when possible.
  ///
  /// If tools are registered after [initialized] completes, then the server
  /// will notify the client
  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) async {
    _peer.registerMethod(
      ListToolsRequest.methodName,
      convertParameters(_listTools),
    );

    _peer.registerMethod(
      CallToolRequest.methodName,
      convertParameters(_callTool),
    );
    var result = await super.initialize(request);
    (result.capabilities.tools ??= Tools()).listChanged = true;
    return result;
  }

  /// Register [tool] to call [impl] when invoked.
  ///
  /// If this server is already initialized and still connected to a client,
  /// then the client will be notified that the tools list has changed.
  ///
  /// Throws a [StateError] if there is already a [Tool] registered with the
  /// same name.
  void registerTool(
    Tool tool,
    FutureOr<CallToolResult> Function(CallToolRequest) impl,
  ) {
    if (_registeredTools.containsKey(tool.name)) {
      throw StateError(
        'Failed to register tool ${tool.name}, it is already registered',
      );
    }
    _registeredTools[tool.name] = tool;
    _registeredToolImpls[tool.name] = impl;

    if (ready) {
      _notifyToolListChanged();
    }
  }

  /// Un-registers a [Tool] by [name].
  ///
  /// Does not error if the tool hasn't been registered yet.
  void unregisterTool(String name) {
    _registeredTools.remove(name);
    _registeredToolImpls.remove(name);
  }

  /// Returns the list of supported tools for this server.
  ListToolsResult _listTools(ListToolsRequest request) =>
      ListToolsResult(tools: [for (var tool in _registeredTools.values) tool]);

  /// Invoked when one of the registered tools is called.
  Future<CallToolResult> _callTool(CallToolRequest request) async {
    final impl = _registeredToolImpls[request.name];
    if (impl == null) {
      return CallToolResult(
        isError: true,
        content: [
          TextContent(text: 'No tool registered with the name ${request.name}'),
        ],
      );
    }

    try {
      return await impl(request);
    } catch (e, s) {
      return CallToolResult(
        isError: true,
        content: [TextContent(text: '$e\n$s')],
      );
    }
  }

  /// Called whenever the list of tools changes, it is the job of the client to
  /// then ask again for the list of tools.
  void _notifyToolListChanged() {
    _peer.sendNotification(
      ToolListChangedNotification.methodName,
      ToolListChangedNotification(),
    );
  }
}
