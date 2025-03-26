// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:meta/meta.dart';
import 'package:stream_channel/stream_channel.dart';

import '../api.dart';
import '../util.dart';

part 'tools_support.dart';
part 'resources_support.dart';

/// Base class to extend when implementing an MCP server.
///
/// Actual functionality beyond server initialization is done by mixing in
/// additional support mixins such as [ToolsSupport], [ResourcesSupport] etc.
abstract base class MCPServer {
  /// Completes when this server has finished initialization and gotten the
  /// final ack from the client.
  FutureOr<void> get initialized => _initialized.future;
  final Completer<void> _initialized = Completer<void>();

  /// Whether this server is still active and has completed initialization.
  bool get ready => !_peer.isClosed && _initialized.isCompleted;

  final Peer _peer;

  /// The name, current version, and other info to give to the client.
  ServerImplementation get implementation;

  /// Instructions for how to use this server, which are given to the client.
  ///
  /// These may be used in system prompts.
  String get instructions;

  MCPServer.fromStreamChannel(StreamChannel<String> channel)
    : _peer = Peer(channel) {
    _peer.registerMethod(
      InitializeRequest.methodName,
      convertParameters(initialize),
    );

    _peer.registerMethod(
      InitializedNotification.methodName,
      convertParameters(handleInitialized),
    );

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
      instructions: instructions,
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
