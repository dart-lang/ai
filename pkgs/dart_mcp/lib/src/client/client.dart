// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:collection';

import 'package:async/async.dart' show StreamExtensions;
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:meta/meta.dart';
import 'package:stream_channel/stream_channel.dart';

import '../../stdio.dart';
import '../api/api.dart';
import '../shared.dart';
import '../utils/constants.dart';

part 'elicitation_support.dart';
part 'roots_support.dart';
part 'sampling_support.dart';

/// The base class for MCP clients.
///
/// Can be directly constructed or extended with additional classes.
///
/// Adding [capabilities] is done through additional support mixins such as
/// [RootsSupport].
///
/// Override the [initialize] function to perform setup logic inside mixins,
/// this will be invoked at the end of base class constructor.
base class MCPClient {
  /// A description of the client sent to servers during initialization.
  final Implementation implementation;

  MCPClient(this.implementation) {
    initialize();
  }

  /// Lifecycle method called in the base class constructor.
  ///
  /// Used to modify the [capabilities] of this client from mixins, or perform
  /// any other initialization that is required.
  void initialize() {}

  /// The capabilities of this client.
  ///
  /// This can be modified by overriding the [initialize] method.
  final ClientCapabilities capabilities = ClientCapabilities();

  @visibleForTesting
  final Set<ServerConnection> connections = {};

  /// Connect to a new MCP server over [stdin] and [stdout], where these
  /// correspond to the stdio streams of the server process (not the client).
  ///
  /// If [protocolLogSink] is provided, all messages sent between the client and
  /// server will be forwarded to that [Sink] as well, with `<<<` preceding
  /// incoming messages and `>>>` preceding outgoing messages. It is the
  /// responsibility of the caller to close this sink.
  ///
  /// If [onDone] is passed, it will be invoked when the connection shuts down.
  @Deprecated('Use stdioChannel and connectServer instead.')
  ServerConnection connectStdioServer(
    StreamSink<List<int>> stdin,
    Stream<List<int>> stdout, {
    Sink<String>? protocolLogSink,
    void Function()? onDone,
  }) {
    final channel = stdioChannel(input: stdout, output: stdin);
    final connection = connectServer(channel, protocolLogSink: protocolLogSink);
    if (onDone != null) connection.done.then((_) => onDone());
    return connection;
  }

  /// Returns a connection for an MCP server using a [channel], which is already
  /// established.
  ///
  /// Each map sent over [channel] is a single decoded JSON-RPC message.
  ///
  /// If [protocolLogSink] is provided, all messages sent on [channel] will be
  /// forwarded to that [Sink] as well, with `<<<` preceding incoming messages
  /// and `>>>` preceding outgoing messages. It is the responsibility of the
  /// caller to close this sink.
  ///
  /// To perform cleanup when this connection is closed, use the
  /// [ServerConnection.done] future.
  ServerConnection connectServer(
    StreamChannel<Map<String, Object?>> channel, {
    Sink<String>? protocolLogSink,
  }) {
    // For type promotion in this function.
    final self = this;
    final connection = ServerConnection.fromStreamChannel(
      channel,
      protocolLogSink: protocolLogSink,
      rootsSupport: self is RootsSupport ? self : null,
      samplingSupport: self is SamplingSupport ? self : null,
      elicitationFormSupport: self is ElicitationFormSupport ? self : null,
      elicitationUrlSupport: self is ElicitationUrlSupport ? self : null,
    );
    connections.add(connection);
    channel.sink.done.then((_) => connections.remove(connection));
    return connection;
  }

  /// Shuts down all active server connections.
  Future<void> shutdown() async {
    final connections = this.connections.toList();
    this.connections.clear();
    await Future.wait([
      for (var connection in connections) connection.shutdown(),
    ]);
  }
}

/// An active server connection.
base class ServerConnection extends MCPBase {
  /// The version of the protocol that was negotiated during initialization.
  ///
  /// Some APIs may error if you attempt to use them without first checking the
  /// protocol version.
  late ProtocolVersion protocolVersion;

  /// The [Implementation] returned from the [initialize] request.
  ///
  /// Only non-null after [initialize] has successfully completed.
  Implementation? serverInfo;

  /// The [ServerCapabilities] returned from the [initialize] request.
  ///
  /// Only assigned after [initialize] has successfully completed.
  late ServerCapabilities serverCapabilities;

  /// The [ElicitationUrlSupport] for this connection, if any.
  final ElicitationUrlSupport? _elicitationUrlSupport;

  /// The [ElicitationFormSupport] for this connection, if any.
  final ElicitationFormSupport? _elicitationFormSupport;

  /// The [SamplingSupport] for this connection, if any.
  final SamplingSupport? _samplingSupport;

  /// The [RootsSupport] for this connection, if any.
  final RootsSupport? _rootsSupport;

  /// Maximum number of automatic retries for an `input_required` result.
  ///
  /// This prevents an unbounded loop and matches the TypeScript and Python SDK
  /// defaults.
  static const _maxInputRequiredRounds = 10;

  @override
  String get name => serverInfo?.name ?? super.name;

  /// Emits an event any time the server notifies us of a change to the list of
  /// prompts it supports.
  ///
  /// This is a broadcast stream, events are not buffered and only future events
  /// are given.
  Stream<PromptListChangedNotification?> get promptListChanged =>
      _promptListChangedController.stream;
  final _promptListChangedController =
      StreamController<PromptListChangedNotification?>.broadcast();

  /// Emits an event any time the server notifies us of a change to the list of
  /// tools it supports.
  ///
  /// This is a broadcast stream, events are not buffered and only future events
  /// are given.
  Stream<ToolListChangedNotification?> get toolListChanged =>
      _toolListChangedController.stream;
  final _toolListChangedController =
      StreamController<ToolListChangedNotification?>.broadcast();

  /// Emits an event any time the server notifies us of a change to the list of
  /// resources it supports.
  ///
  /// This is a broadcast stream, events are not buffered and only future events
  /// are given.
  Stream<ResourceListChangedNotification?> get resourceListChanged =>
      _resourceListChangedController.stream;
  final _resourceListChangedController =
      StreamController<ResourceListChangedNotification?>.broadcast();

  /// Emits an event any time the server notifies us of a change to a resource
  /// that this client has subscribed to.
  ///
  /// This is a broadcast stream, events are not buffered and only future events
  /// are given.
  Stream<ResourceUpdatedNotification> get resourceUpdated =>
      _resourceUpdatedController.stream;
  final _resourceUpdatedController =
      StreamController<ResourceUpdatedNotification>.broadcast();

  /// Emits an event any time the server sends a log message.
  ///
  /// This is a broadcast stream, events are not buffered and only future events
  /// are given.
  Stream<LoggingMessageNotification> get onLog => _logController.stream;
  final _logController =
      StreamController<LoggingMessageNotification>.broadcast();

  /// Emits an event any time the server sends an elicitation complete
  /// notification.
  ///
  /// This is a broadcast stream, events are not buffered and only future events
  /// are given.
  Stream<ElicitationCompleteNotification> get onElicitationComplete =>
      _elicitationCompleteController.stream;
  final _elicitationCompleteController =
      StreamController<ElicitationCompleteNotification>.broadcast();

  /// A 1:1 connection from a client to a server using [channel].
  ///
  /// If the client supports "roots", then it should provide an implementation
  /// through [rootsSupport].
  ///
  /// If the client supports "sampling", then it should provide an
  /// implementation through [samplingSupport].
  ServerConnection.fromStreamChannel(
    super.channel, {
    super.protocolLogSink,
    RootsSupport? rootsSupport,
    SamplingSupport? samplingSupport,
    @Deprecated('Use elicitationFormSupport instead')
    ElicitationSupport? elicitationSupport,
    ElicitationFormSupport? elicitationFormSupport,
    ElicitationUrlSupport? elicitationUrlSupport,
  }) : _elicitationFormSupport = elicitationFormSupport ?? elicitationSupport,
       _elicitationUrlSupport = elicitationUrlSupport,
       _samplingSupport = samplingSupport,
       _rootsSupport = rootsSupport {
    if (rootsSupport != null) {
      registerRequestHandler(
        ListRootsRequest.methodName,
        rootsSupport.handleListRoots,
      );
    }

    if (samplingSupport != null) {
      registerRequestHandler(
        CreateMessageRequest.methodName,
        (CreateMessageRequest request) =>
            samplingSupport.handleCreateMessage(request, serverInfo!),
      );
    }

    if (_elicitationFormSupport != null || elicitationUrlSupport != null) {
      registerRequestHandler(ElicitRequest.methodName, (ElicitRequest request) {
        final raw = request.rawMode;
        if (raw != null && !ElicitationMode.values.any((m) => m.name == raw)) {
          throw RpcException.invalidParams(
            'The elicitation mode was "$raw", which is not one of: '
            '${ElicitationMode.values.map((m) => m.name).join(', ')}',
          );
        }
        switch (request.mode) {
          case ElicitationMode.form:
            final formSupport = _elicitationFormSupport;
            if (formSupport == null) {
              throw RpcException.invalidParams(
                'This client did not declare the elicitation.form capability',
              );
            }
            return formSupport.handleElicitation(request, this);
          case ElicitationMode.url:
            if (elicitationUrlSupport == null) {
              throw RpcException.invalidParams(
                'This client did not declare the elicitation.url capability',
              );
            }
            return elicitationUrlSupport.handleElicitation(request, this);
        }
      });
    }

    registerNotificationHandler(
      PromptListChangedNotification.methodName,
      _promptListChangedController.sink.add,
    );

    registerNotificationHandler(
      ToolListChangedNotification.methodName,
      _toolListChangedController.sink.add,
    );

    registerNotificationHandler(
      ResourceListChangedNotification.methodName,
      _resourceListChangedController.sink.add,
    );

    registerNotificationHandler(
      ResourceUpdatedNotification.methodName,
      _resourceUpdatedController.sink.add,
    );

    registerNotificationHandler(
      LoggingMessageNotification.methodName,
      _logController.sink.add,
    );

    registerNotificationHandler(
      ElicitationCompleteNotification.methodName,
      _elicitationCompleteController.sink.add,
    );
  }

  /// Close all connections and streams so the process can cleanly exit.
  @override
  Future<void> shutdown() async {
    await Future.wait([
      super.shutdown(),
      _promptListChangedController.close(),
      _toolListChangedController.close(),
      _resourceListChangedController.close(),
      _resourceUpdatedController.close(),
      _logController.close(),
    ]);
  }

  /// Called after a successful call to [initialize].
  void notifyInitialized([InitializedNotification? notification]) =>
      sendNotification(InitializedNotification.methodName, notification);

  /// Initializes the server, this should be done before anything else.
  ///
  /// The client must call [notifyInitialized] after receiving and accepting
  /// this response.
  ///
  /// Throws a [StateError] if initialization fails for unknown reasons (usually
  /// the server connection closes prematurely due to misconfiguration). To
  /// debug these errors you should pass a `protocolLogSink` when creating these
  /// connections.
  Future<InitializeResult> initialize(InitializeRequest request) async {
    final response = await sendRequest<InitializeResult>(
      InitializeRequest.methodName,
      request,
    );
    serverInfo = response.serverInfo;
    serverCapabilities = response.capabilities;
    final serverVersion = response.protocolVersion;
    if (serverVersion == null || !serverVersion.isSupported) {
      await shutdown();
    } else {
      protocolVersion = serverVersion;
    }
    return response;
  }

  /// List all the tools from this server.
  Future<ListToolsResult> listTools([ListToolsRequest? request]) =>
      sendRequest(ListToolsRequest.methodName, request);

  /// Invokes a [Tool] returned from the [ListToolsResult].
  Future<CallToolResult> callTool(CallToolRequest request) async {
    try {
      return await _sendRequestWithInputs(CallToolRequest.methodName, request);
    } on RpcException catch (e) {
      // If we are set up to try and auto handle url elicitation and we get
      // an error that the url elicitation is required, we will try and handle
      // it and then retry the request a single time.
      final data = e.data;
      if (_elicitationUrlSupport?.autoHandleUrlElicitationRequired == true &&
          e.code == McpErrorCodes.urlElicitationRequired &&
          data is Map &&
          // The schema makes `mode` required on a url elicitation, so a
          // payload naming anything else does not belong on this path. Read
          // it off the raw map, since the error is whatever the peer sent.
          data[Keys.mode] == ElicitationMode.url.name) {
        // `RpcException.serialize` spreads the error data into an untyped map
        // literal (adding a `request` key), so the map arriving here is not a
        // `Map<String, Object?>` and a representation type check against
        // `ElicitRequest` would fail. Restore the typed view instead.
        final elicitRequest = data.cast<String, Object?>() as ElicitRequest;
        final elicitationComplete =
            elicitRequest.onElicitationComplete(this).firstOrNull;
        final elicitResult = await _elicitationUrlSupport!.handleElicitation(
          elicitRequest,
          this,
        );
        if (elicitResult.action == ElicitationAction.accept) {
          await elicitationComplete;
          return await _sendRequestWithInputs(
            CallToolRequest.methodName,
            request,
          );
        }
      }
      rethrow;
    }
  }

  /// Lists all the [Resource]s from this server.
  Future<ListResourcesResult> listResources([ListResourcesRequest? request]) =>
      sendRequest(ListResourcesRequest.methodName, request);

  /// Reads a [Resource] returned from the [ListResourcesResult] or matching
  /// a [ResourceTemplate] from a [ListResourceTemplatesResult].
  Future<ReadResourceResult> readResource(ReadResourceRequest request) =>
      _sendRequestWithInputs(ReadResourceRequest.methodName, request);

  /// Lists all the [ResourceTemplate]s from this server.
  Future<ListResourceTemplatesResult> listResourceTemplates([
    ListResourceTemplatesRequest? request,
  ]) => sendRequest(ListResourceTemplatesRequest.methodName, request);

  /// Lists all the prompts from this server.
  Future<ListPromptsResult> listPrompts([ListPromptsRequest? request]) =>
      sendRequest(ListPromptsRequest.methodName, request);

  /// Gets the requested [Prompt] from the server.
  Future<GetPromptResult> getPrompt(GetPromptRequest request) =>
      _sendRequestWithInputs(GetPromptRequest.methodName, request);

  Future<T> _sendRequestWithInputs<T extends Result>(
    String methodName,
    WithInputResponses request,
  ) async {
    if (serverInfo == null || protocolVersion < ProtocolVersion.v2026_07_28) {
      return sendRequest<T>(methodName, request);
    }
    try {
      return await _retryWhileInputRequired<T>(methodName, request);
    } finally {
      // Every round runs under the progress token the caller put on the first
      // request, so the stream it opened outlives all of them.
      await closeProgress(request);
    }
  }

  Future<T> _retryWhileInputRequired<T extends Result>(
    String methodName,
    WithInputResponses request,
  ) async {
    final originalRequest = request as Map<String, Object?>;
    var result =
        (await sendRequestKeepingProgress<T>(methodName, request)) as Result;
    for (
      var round = 0;
      result.resultType == ResultTypes.inputRequired;
      round++
    ) {
      if (round == _maxInputRequiredRounds) {
        throw StateError(
          'The server returned `${ResultTypes.inputRequired}` after '
          '$_maxInputRequiredRounds retries for `$methodName`. Expected '
          '`${ResultTypes.complete}`.',
        );
      }
      final inputRequired = result as InputRequiredResult;
      final responses = <String, Result>{};
      final inputRequests = inputRequired.inputRequests;
      final requestState = inputRequired.requestState;
      if (inputRequests == null && requestState == null) {
        throw StateError(
          'The server returned `${ResultTypes.inputRequired}` without '
          '`${Keys.inputRequests}` or `${Keys.requestState}`.',
        );
      }
      // TODO: Pace a leg carrying only request state, which nothing else slows
      // down, the way the TypeScript and Python SDKs do.
      if (inputRequests != null) {
        final handlers = [
          for (final entry in inputRequests.entries)
            MapEntry(entry.key, _inputRequestHandler(entry.value)),
        ];
        for (final handler in handlers) {
          responses[handler.key] = await handler.value();
        }
      }
      final retryRequest =
          <String, Object?>{
                for (final entry in originalRequest.entries)
                  if (entry.key != Keys.inputResponses &&
                      entry.key != Keys.requestState)
                    entry.key: entry.value,
                if (responses.isNotEmpty) Keys.inputResponses: responses,
                if (requestState != null) Keys.requestState: requestState,
              }
              as WithInputResponses;
      result =
          (await sendRequestKeepingProgress<T>(methodName, retryRequest))
              as Result;
    }
    return result as T;
  }

  Future<Result> Function() _inputRequestHandler(InputRequest inputRequest) {
    switch (inputRequest.method) {
      case ElicitRequest.methodName:
        final request =
            _inputRequestParams(inputRequest, required: true)! as ElicitRequest;
        final raw = request.rawMode;
        if (raw != null && !ElicitationMode.values.any((m) => m.name == raw)) {
          throw StateError(
            'The elicitation mode was "$raw", which is not one of: '
            '${ElicitationMode.values.map((m) => m.name).join(', ')}',
          );
        }
        switch (request.mode) {
          case ElicitationMode.form:
            final support = _elicitationFormSupport;
            if (support == null) {
              throw _undeclaredCapability('elicitation.form');
            }
            return () async => await support.handleElicitation(request, this);
          case ElicitationMode.url:
            final support = _elicitationUrlSupport;
            if (support == null) {
              throw _undeclaredCapability('elicitation.url');
            }
            return () async => await support.handleElicitation(request, this);
        }
      case CreateMessageRequest.methodName:
        final support = _samplingSupport;
        if (support == null) {
          throw _undeclaredCapability(Keys.sampling);
        }
        final request =
            _inputRequestParams(inputRequest, required: true)!
                as CreateMessageRequest;
        final serverInfo = this.serverInfo!;
        return () async =>
            await support.handleCreateMessage(request, serverInfo);
      case ListRootsRequest.methodName:
        final support = _rootsSupport;
        if (support == null) {
          throw _undeclaredCapability(Keys.roots);
        }
        final request =
            _inputRequestParams(inputRequest, required: false)
                as ListRootsRequest?;
        return () async => await support.handleListRoots(request);
      default:
        throw StateError(
          'The input request method was "${inputRequest.method}", which is '
          'not one of: ${ElicitRequest.methodName}, '
          '${CreateMessageRequest.methodName}, ${ListRootsRequest.methodName}',
        );
    }
  }

  /// Subscribes this client to a resource by URI (at `request.uri`).
  ///
  /// Updates will come on the [resourceUpdated] stream.
  Future<void> subscribeResource(SubscribeRequest request) =>
      sendRequest(SubscribeRequest.methodName, request);

  /// Unsubscribes this client to a resource by URI (at `request.uri`).
  ///
  /// Updates will come on the [resourceUpdated] stream.
  Future<void> unsubscribeResource(UnsubscribeRequest request) =>
      sendRequest(UnsubscribeRequest.methodName, request);

  /// Sends a request to change the current logging level.
  ///
  /// Completes when the response is received.
  Future<void> setLogLevel(SetLevelRequest request) =>
      sendRequest(SetLevelRequest.methodName, request);

  /// Sends a request to get completions from the server.
  ///
  /// Clients should debounce their calls to this API to avoid overloading the
  /// server.
  ///
  /// You should check the [protocolVersion] before using this API, it must be
  /// >= [ProtocolVersion.v2025_03_26].
  // TODO: Implement automatic debouncing.
  Future<CompleteResult> requestCompletions(CompleteRequest request) =>
      sendRequest(CompleteRequest.methodName, request);
}

Map<String, Object?>? _inputRequestParams(
  InputRequest inputRequest, {
  required bool required,
}) {
  final params = (inputRequest as Map<String, Object?>)[Keys.params];
  if (params == null && !required) return null;
  if (params is! Map) {
    throw StateError(
      'The input request params for "${inputRequest.method}" were '
      '${params.runtimeType}, expected an object.',
    );
  }
  return params.cast<String, Object?>();
}

StateError _undeclaredCapability(String capability) => StateError(
  'The server sent an input request needing the $capability capability, '
  'which this client did not declare.',
);

extension ElicitationServerConnection on ElicitRequest {
  /// Broadcast stream of notifications for this elicitation ID. Events are not
  /// buffered so you must listen to this stream prior to opening the URL or
  /// you may miss the notification.
  ///
  /// Typically you should call `.take(1)` or `.first` on this stream to
  /// automatically cancel the subscription after receiving the first
  /// notification.
  Stream<void> onElicitationComplete(ServerConnection connection) {
    return connection.onElicitationComplete.where(
      (notification) => notification.elicitationId == elicitationId,
    );
  }
}
