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

/// The first protocol revision which replaced the `initialize` handshake with
/// `server/discover` and per-request client context.
const _firstRequestScopedVersion = ProtocolVersion.v2026_07_28;

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

  /// The capabilities [initialize] registered, which [discover] advertises.
  ///
  /// This is the object [initialize] builds, and mixins and subclasses edit it
  /// on their way back up rather than replacing it, so it ends up carrying
  /// every feature they registered.
  ///
  /// Only assigned after [initialize] has been called.
  late ServerCapabilities _capabilities;

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
    // Registering this handler is itself a statement about the lifecycle, so
    // only a server on a request-scoped revision does it. A client probing
    // under the stdio backward compatibility rules would read an answer here
    // as "this connection is modern".
    if (protocolVersion >= _firstRequestScopedVersion) {
      registerRequestHandler(DiscoverRequest.methodName, discover);
    }
    return _capabilities = ServerCapabilities();
  }

  /// Answers the `server/discover` request with the protocol versions this
  /// server serves, the capabilities [initialize] registered, and the
  /// instructions it was given.
  ///
  /// Only the revisions from [ProtocolVersion.v2026_07_28] on are advertised:
  /// earlier ones are negotiated with the legacy `initialize` handshake, which
  /// this request replaced. A transport which serves a narrower set than this
  /// package implements rejects the versions it does not serve itself, the way
  /// `handleStreamableHttpRequest` does with its own version header check.
  ///
  /// The request-scoped dispatcher fills in the rest of what the schema
  /// requires, `resultType` and the caching hints, and stamps the server's
  /// identity into `_meta`. This only answers the fields which are specific to
  /// discovery. Override it to advertise something else.
  ///
  /// The request has no parameters of its own beyond the `_meta` envelope, and
  /// the per-request context that envelope carries reaches a server through
  /// [initialize] rather than through here, so it is optional the way the other
  /// requests without parameters are.
  ///
  /// https://modelcontextprotocol.io/specification/2026-07-28/server/discover
  FutureOr<DiscoverResult> discover([DiscoverRequest? request]) =>
      DiscoverResult(
        supportedVersions: [
          for (final version in ProtocolVersion.values)
            if (version >= _firstRequestScopedVersion) version.versionString,
        ],
        capabilities: _capabilities,
        instructions: instructions,
      );

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
