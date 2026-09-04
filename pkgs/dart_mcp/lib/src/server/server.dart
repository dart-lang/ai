// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:collection';

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
part 'subscriptions_support.dart';
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
    this.logLevel,
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

  /// The log level the client asked for on this request, if any.
  ///
  /// Request-scoped transports read this from the reserved
  /// `io.modelcontextprotocol/logLevel` request metadata key, see
  /// https://modelcontextprotocol.io/specification/2026-07-28/server/utilities/logging.
  /// On 2026-07-28 [LoggingSupport.initialize] copies this onto
  /// [LoggingSupport.loggingLevel], `null` included. That revision took
  /// `logging/setLevel` out, and [LoggingSupport] does not register it. The
  /// legacy handshake has no per-request level and leaves this null, so the
  /// level starts at [LoggingLevel.warning] unless the server picked one for
  /// itself, and `logging/setLevel` moves it from there.
  final LoggingLevel? logLevel;
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

  /// The capabilities of this server, which [discover] advertises.
  ///
  /// This can be modified by overriding the [initialize] method.
  final ServerCapabilities capabilities = ServerCapabilities();

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
  /// in this method, as well as editing [capabilities].
  ///
  /// Transport-specific initialization, including the legacy MCP initialize
  /// request, is handled separately.
  FutureOr<void> initialize(MCPServerInitialization initialization) {
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
    if (protocolVersion.methodIsValid(DiscoverRequest.methodName)) {
      registerRequestHandler(DiscoverRequest.methodName, discover);
    }
  }

  /// Answers the `server/discover` request with the protocol versions this
  /// server serves, the capabilities [initialize] registered, and the
  /// instructions it was given.
  ///
  /// Only the revisions from [ProtocolVersion.v2026_07_28] on are advertised:
  /// earlier ones are negotiated with the legacy `initialize` handshake, which
  /// this request replaced. A transport that serves a narrower set than this
  /// package implements rejects the versions it does not serve itself, the way
  /// `handleStreamableHttpRequest` does with its own version header check.
  ///
  /// The request-scoped dispatcher fills in the rest of what the schema
  /// requires, `resultType` and the caching hints, and stamps the server's
  /// identity into `_meta`. This only answers the fields that are specific to
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
            if (version.methodIsValid(DiscoverRequest.methodName))
              version.versionString,
        ],
        capabilities: _advertisedCapabilities,
        instructions: instructions,
      );

  /// The capabilities [discover] advertises.
  ///
  /// On these revisions a client only hears a list change or a resource update
  /// over a `subscriptions/listen` stream it opened with the matching
  /// `promptsListChanged`, `toolsListChanged`, `resourcesListChanged` or
  /// `resourceSubscriptions` filter. [SubscriptionsSupport] acknowledges the
  /// request, and the Streamable HTTP transport routes matching notifications
  /// from that request's server. A server with [SubscriptionsSupport] therefore
  /// advertises the capabilities it registered. Without that mixin the four
  /// bits standing for those notifications come off here: `listChanged` on
  /// each of the three, and `subscribe` on [ServerCapabilities.resources].
  /// Every other key the server registered is passed through, and
  /// `initializeLegacy` keeps all of them, since the revisions that handshake
  /// negotiates still serve `resources/subscribe` and send the list changes
  /// without a filter.
  ServerCapabilities get _advertisedCapabilities =>
      this is SubscriptionsSupport
          ? ServerCapabilities.fromMap({
            ...capabilities as Map<String, Object?>,
          })
          : ServerCapabilities.fromMap({
            ...capabilities as Map<String, Object?>,
            if (capabilities.prompts case final prompts?)
              Keys.prompts: Prompts.fromMap(
                Map<String, Object?>.from(prompts as Map<String, Object?>)
                  ..remove(Keys.listChanged),
              ),
            if (capabilities.resources case final resources?)
              Keys.resources: Resources.fromMap(
                Map<String, Object?>.from(resources as Map<String, Object?>)
                  ..remove(Keys.listChanged)
                  ..remove(Keys.subscribe),
              ),
            if (capabilities.tools case final tools?)
              Keys.tools: Tools.fromMap(
                Map<String, Object?>.from(tools as Map<String, Object?>)
                  ..remove(Keys.listChanged),
              ),
          });

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
    await initialize(
      MCPServerInitialization(
        protocolVersion: negotiatedProtocolVersion,
        clientCapabilities: request.capabilities,
        clientInfo: request.clientInfo,
      ),
    );
    return InitializeResult(
      protocolVersion: negotiatedProtocolVersion,
      serverCapabilities: capabilities,
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

  /// Whether or not the connected client supports [listRoots].
  ///
  /// Only safe to call after calling [initialize] on `super` since this
  /// is based on the client capabilities.
  bool get supportsRoots => clientCapabilities.supportsRoots;

  /// Whether or not the connected client supports [createMessage].
  ///
  /// Only safe to call after calling [initialize] on `super` since this
  /// is based on the client capabilities.
  bool get supportsSampling => clientCapabilities.supportsSampling;

  /// Lists all the root URIs from the client.
  ///
  /// Throws an [RpcException] when [protocolVersion] does not have
  /// `roots/list`. 2026-07-28 took it out, and carries a [ListRootsRequest]
  /// in an [InputRequiredResult] instead.
  ///
  /// Otherwise this only succeeds if the client has advertised the `roots`
  /// capability, and throws an [RpcException] with
  /// [McpErrorCodes.missingRequiredClientCapability] when it has not, naming
  /// the capability the client is missing under `data.requiredCapabilities`.
  @Deprecated(
    'Use `InputRequiredResult` for 2026-07-28. '
    'Older supported revisions keep this method.',
  )
  Future<ListRootsResult> listRoots([ListRootsRequest? request]) async {
    _rejectRemovedMethod(ListRootsRequest.methodName, protocolVersion);
    if (!supportsRoots) {
      throw _missingRoots;
    }
    return sendRequest(ListRootsRequest.methodName, request);
  }

  /// A request to prompt the LLM owned by the client with a message.
  ///
  /// See https://modelcontextprotocol.io/specification/2026-07-28/client/sampling/.
  ///
  /// Throws an [RpcException] when [protocolVersion] does not have
  /// `sampling/createMessage`. 2026-07-28 took it out, and carries a
  /// [CreateMessageRequest] in an [InputRequiredResult] instead.
  ///
  /// Otherwise this only succeeds if the client has advertised the `sampling`
  /// capability, and throws an [RpcException] with
  /// [McpErrorCodes.missingRequiredClientCapability] when it has not, naming
  /// the capability the client is missing under `data.requiredCapabilities`.
  @Deprecated(
    'Use `InputRequiredResult` for 2026-07-28. '
    'Older supported revisions keep this method.',
  )
  Future<CreateMessageResult> createMessage(
    CreateMessageRequest request,
  ) async {
    _rejectRemovedMethod(CreateMessageRequest.methodName, protocolVersion);
    if (!supportsSampling) {
      throw _missingSampling;
    }
    return sendRequest(CreateMessageRequest.methodName, request);
  }
}

/// Refuses to send [method] when [ProtocolVersion.methodIsValid] says
/// [protocolVersion] does not have it.
///
/// Each sender calls this first, so a method the revision does not have fails
/// for that reason instead of for a missing client capability.
void _rejectRemovedMethod(String method, ProtocolVersion protocolVersion) {
  if (protocolVersion.methodIsValid(method)) return;
  // Only a revision with an `InputRequiredResult` can be pointed at it, and
  // `elicit` also lands here on the revisions before 2025-06-18 added
  // `elicitation/create`.
  final replacement =
      protocolVersion >= ProtocolVersion.v2026_07_28
          ? ' Ask the client for input with an InputRequiredResult on '
              '${CallToolRequest.methodName}, ${GetPromptRequest.methodName}, '
              'or ${ReadResourceRequest.methodName} instead.'
          : '';
  throw RpcException(
    error_code.INTERNAL_ERROR,
    'Protocol version ${protocolVersion.versionString} does not have '
    '$method.$replacement',
  );
}

/// The error a server must return when handling a request needs [capability],
/// which the client did not declare, carrying [required] under
/// `data.requiredCapabilities`.
RpcException _missingClientCapability(
  String capability,
  ClientCapabilities required,
) => RpcException(
  McpErrorCodes.missingRequiredClientCapability,
  'The client did not declare the $capability capability',
  data: {Keys.requiredCapabilities: required},
);

/// The refusal for a client that did not declare `roots`.
RpcException get _missingRoots => _missingClientCapability(
  'roots',
  ClientCapabilities(roots: RootsCapabilities()),
);

/// The refusal for a client that did not declare `sampling`.
RpcException get _missingSampling =>
    _missingClientCapability('sampling', ClientCapabilities(sampling: {}));

/// The refusal for a client whose `sampling` left out `tools`.
RpcException get _missingSamplingTools => _missingClientCapability(
  'sampling.tools',
  ClientCapabilities(sampling: {Keys.tools: <String, Object?>{}}),
);

/// The refusal for a client that did not declare `elicitation.form`.
RpcException get _missingFormElicitation => _missingClientCapability(
  'elicitation.form',
  ClientCapabilities(elicitation: ElicitationCapability(form: {})),
);

/// The refusal for a client that did not declare `elicitation.url`.
RpcException get _missingUrlElicitation => _missingClientCapability(
  'elicitation.url',
  ClientCapabilities(elicitation: ElicitationCapability(url: {})),
);

/// The client capability reads a server makes, on the capabilities themselves
/// so that [handleRequestScopedMessage] can make them without a server.
///
/// [MCPServer] and [ElicitationRequestSupport] expose and document all of
/// these but [supportsSamplingTools], which only the input request guard
/// needs.
extension on ClientCapabilities {
  bool get supportsRoots => roots != null;

  bool get supportsSampling => sampling != null;

  /// Whether or not the client can answer a sampling request carrying `tools`
  /// or `toolChoice`.
  bool get supportsSamplingTools => sampling?[Keys.tools] != null;

  bool get supportsFormElicitation {
    final elicitation = this.elicitation;
    if (elicitation == null) return false;
    return elicitation.form != null ||
        (elicitation as Map<String, Object?>).isEmpty;
  }

  bool get supportsUrlElicitation => elicitation?.url != null;
}
