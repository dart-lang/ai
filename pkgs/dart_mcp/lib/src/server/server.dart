// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:meta/meta.dart';
import 'package:stream_channel/stream_channel.dart';

import '../api/api.dart';
import '../shared.dart';

part 'completions_support.dart';
part 'logging_support.dart';
part 'prompts_support.dart';
part 'resources_support.dart';
part 'tools_support.dart';

/// Base class to extend when implementing an MCP server.
///
/// Actual functionality beyond server initialization is done by mixing in
/// additional support mixins such as [ToolsSupport], [ResourcesSupport] etc.
abstract base class MCPServer extends MCPBase {
  /// Completes when this server has finished initialization and gotten the
  /// final ack from the client.
  Future<void> get initialized => _initialized.future;
  final Completer<void> _initialized = Completer<void>();

  /// Whether this server is still active and has completed initialization.
  bool get ready => isActive && _initialized.isCompleted;

  /// The name, current version, and other info to give to the client.
  final ServerImplementation implementation;

  /// Instructions for how to use this server, which are given to the client.
  ///
  /// These may be used in system prompts.
  final String instructions;

  /// The negotiated protocol version.
  ///
  /// Only assigned after `initialize` has been called.
  late ProtocolVersion protocolVersion;

  /// The capabilities of the client.
  ///
  /// Only assigned after `initialize` has been called.
  late ClientCapabilities clientCapabilities;

  /// Emits an event any time the client notifies us of a change to the list of
  /// roots it supports.
  ///
  /// If `null` then the client doesn't support these notifications.
  ///
  /// This is a broadcast stream, events are not buffered and only future events
  /// are given.
  Stream<RootsListChangedNotification>? get rootsListChanged =>
      _rootsListChangedController?.stream;
  StreamController<RootsListChangedNotification>? _rootsListChangedController;

  MCPServer.fromStreamChannel({
    required this.implementation,
    required this.instructions,
    required StreamChannel<String> channel,
  }) : super(Peer(channel)) {
    registerRequestHandler(InitializeRequest.methodName, initialize);

    registerNotificationHandler(
      InitializedNotification.methodName,
      handleInitialized,
    );
  }

  @override
  Future<void> shutdown() async {
    await super.shutdown();
    await _rootsListChangedController?.close();
  }

  @mustCallSuper
  /// Mixins should register their methods in this method, as well as editing
  /// the [InitializeResult.capabilities] as needed.
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    // If we don't support or understand the version, set it to the latest one
    // that we do support. If the client doesn't support that version they will
    // terminate the connection.
    final clientProtocolVersion = request.protocolVersion;
    if (clientProtocolVersion == null || !clientProtocolVersion.isSupported) {
      protocolVersion = ProtocolVersion.latestSupported;
    } else {
      protocolVersion = clientProtocolVersion;
    }

    clientCapabilities = request.capabilities;
    if (clientCapabilities.roots?.listChanged == true) {
      _rootsListChangedController =
          StreamController<RootsListChangedNotification>.broadcast();
      registerNotificationHandler(
        RootsListChangedNotification.methodName,
        _rootsListChangedController!.sink.add,
      );
    }
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

  /// Lists all the root URIs from the client.
  Future<ListRootsResult> listRoots(ListRootsRequest request) =>
      sendRequest(ListRootsRequest.methodName, request);

  /// A request to prompt the LLM owned by the client with a message.
  ///
  /// See https://spec.modelcontextprotocol.io/specification/2024-11-05/client/sampling/.
  Future<CreateMessageResult> createMessage(CreateMessageRequest request) =>
      sendRequest(CreateMessageRequest.methodName, request);
}
