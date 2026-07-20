// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:json_rpc_2/error_code.dart' as error_code;
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:meta/meta.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:stream_transform/stream_transform.dart';

import '../api/api.dart';
import '../shared.dart';
import '../utils/constants.dart';
import '../utils/json_rpc_2_object.dart';

part 'completions_support.dart';
part 'elicitation_request_support.dart';
part 'logging_support.dart';
part 'prompts_support.dart';
part 'request_scoped.dart';
part 'resources_support.dart';
part 'roots_tracking_support.dart';
part 'tools_support.dart';

/// The client context used to initialize an [MCPServer].
///
/// Legacy transports provide this once per connection after negotiating a
/// protocol version. Request-scoped transports provide it once per request.
final class MCPServerInitialization {
  const MCPServerInitialization({
    required this.protocolVersion,
    required this.clientCapabilities,
    this.clientInfo,
  });

  /// The protocol version used for this connection or request.
  final ProtocolVersion protocolVersion;

  /// The capabilities declared by the client.
  final ClientCapabilities clientCapabilities;

  /// The implementation information declared by the client, if any.
  ///
  /// The legacy handshake always provides this. Request-scoped transports may
  /// omit it, since clients are not required to send it on every request.
  final Implementation? clientInfo;
}

/// Base class to extend when implementing an MCP server.
///
/// Actual functionality beyond server initialization is done by mixing in
/// additional support mixins such as [ToolsSupport], [ResourcesSupport] etc.
abstract base class MCPServer extends MCPBase {
  /// Completes when this server has finished initialization.
  ///
  /// Legacy transports complete this after the final acknowledgement from the
  /// client. Request-scoped transports should call [handleInitialized] after
  /// [initialize] and any transport-specific setup have completed.
  Future<InitializedNotification?> get initialized => _initialized.future;
  final Completer<InitializedNotification?> _initialized = Completer();

  /// Whether this server is still active and has completed initialization.
  bool get ready => isActive && _initialized.isCompleted;

  /// The name, current version, and other info to give to the client.
  final Implementation implementation;

  /// Instructions for how to use this server, which are given to the client.
  ///
  /// These may be used in system prompts.
  final String? instructions;

  /// The negotiated protocol version.
  ///
  /// Only assigned after [initialize] has been called.
  late ProtocolVersion protocolVersion;

  /// The capabilities of the client.
  ///
  /// Only assigned after [initialize] has been called.
  late ClientCapabilities clientCapabilities;

  /// The client implementation information provided during initialization.
  ///
  /// `null` until [initialize] has been called, and remains `null` when the
  /// client did not declare any implementation information.
  Implementation? clientInfo;

  @override
  String get name => implementation.name;

  /// Emits an event any time the client notifies us of a change to the list of
  /// roots it supports.
  ///
  /// If `null` then the client doesn't support these notifications.
  ///
  /// This is a broadcast stream, events are not buffered and only future events
  /// are given.
  Stream<RootsListChangedNotification?>? get rootsListChanged =>
      _rootsListChangedController?.stream;
  StreamController<RootsListChangedNotification?>? _rootsListChangedController;

  MCPServer.fromStreamChannel(
    super.channel, {
    required this.implementation,
    this.instructions,
    super.protocolLogSink,
  }) {
    registerRequestHandler(InitializeRequest.methodName, initializeLegacy);

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
  /// Registers the features available to a client with [initialization].
  ///
  /// Mixins and subclasses should register request handlers and other features
  /// in this method, as well as editing the returned [ServerCapabilities].
  ///
  /// Transport-specific initialization, including the legacy MCP initialize
  /// request, is handled separately.
  FutureOr<ServerCapabilities> initialize(
    MCPServerInitialization initialization,
  ) {
    protocolVersion = initialization.protocolVersion;
    clientCapabilities = initialization.clientCapabilities;
    clientInfo = initialization.clientInfo;
    if (clientCapabilities.roots?.listChanged == true) {
      _rootsListChangedController =
          StreamController<RootsListChangedNotification?>.broadcast();
      registerNotificationHandler(
        RootsListChangedNotification.methodName,
        _rootsListChangedController!.sink.add,
      );
    }
    return ServerCapabilities();
  }

  @mustCallSuper
  /// Handles the initialize request used by legacy MCP protocols.
  ///
  /// Most servers should override [initialize] to register features. Override
  /// this method only to customize legacy protocol negotiation or its wire
  /// response.
  FutureOr<InitializeResult> initializeLegacy(InitializeRequest request) async {
    // If we don't support or understand the version, set it to the latest one
    // that we do support. If the client doesn't support that version they will
    // terminate the connection.
    final clientProtocolVersion = request.protocolVersion;
    final negotiatedProtocolVersion =
        clientProtocolVersion == null || !clientProtocolVersion.isSupported
            ? ProtocolVersion.latestSupported
            : clientProtocolVersion;

    assert(!_initialized.isCompleted);
    final serverCapabilities = await initialize(
      MCPServerInitialization(
        protocolVersion: negotiatedProtocolVersion,
        clientCapabilities: request.capabilities,
        clientInfo: request.clientInfo,
      ),
    );
    return InitializeResult(
      protocolVersion: negotiatedProtocolVersion,
      serverCapabilities: serverCapabilities,
      serverInfo: implementation,
      instructions: instructions,
    );
  }

  /// Completes [initialized].
  ///
  /// Legacy clients call this handler after accepting our [InitializeResult].
  /// Request-scoped transports may call it without a notification after
  /// [initialize] and transport-specific setup have completed.
  ///
  /// The server should not send a response.
  @mustCallSuper
  void handleInitialized([InitializedNotification? notification]) {
    _initialized.complete(notification);
  }

  /// Lists all the root URIs from the client.
  Future<ListRootsResult> listRoots([ListRootsRequest? request]) =>
      sendRequest(ListRootsRequest.methodName, request);

  /// A request to prompt the LLM owned by the client with a message.
  ///
  /// See https://spec.modelcontextprotocol.io/specification/2025-11-05/client/sampling/.
  Future<CreateMessageResult> createMessage(CreateMessageRequest request) =>
      sendRequest(CreateMessageRequest.methodName, request);
}
