// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
// TODO: Refactor to drop this dependency?
import 'dart:io';

import 'package:async/async.dart' hide Result;
import 'package:meta/meta.dart';
import 'package:stream_channel/stream_channel.dart';

import '../api/api.dart';
import '../shared.dart';

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
  final ClientImplementation implementation;

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

  /// Connect to a new MCP server by invoking [command] with [arguments] and
  /// talking to that process over stdin/stdout.
  ///
  /// If [protocolLogSink] is provided, all messages sent between the client and
  /// server will be forwarded to that [Sink] as well, with `<<<` preceding
  /// incoming messages and `>>>` preceding outgoing messages.
  Future<ServerConnection> connectStdioServer(
    String command,
    List<String> arguments, {
    Sink<String>? protocolLogSink,
  }) async {
    final process = await Process.start(command, arguments);
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          stderr.writeln('[StdErr from server $command]: $line');
        });
    final channel = StreamChannel.withCloseGuarantee(
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
    final connection = connectServer(channel, protocolLogSink: protocolLogSink);
    unawaited(connection.done.then((_) => process.kill()));
    return connection;
  }

  /// Returns a connection for an MCP server using a [channel], which is already
  /// established.
  ///
  /// If [protocolLogSink] is provided, all messages sent on [channel] will be
  /// forwarded to that [Sink] as well, with `<<<` preceding incoming messages
  /// and `>>>` preceding outgoing messages.
  ServerConnection connectServer(
    StreamChannel<String> channel, {
    Sink<String>? protocolLogSink,
  }) {
    // For type promotion in this function.
    final self = this;
    final connection = ServerConnection.fromStreamChannel(
      channel,
      protocolLogSink: protocolLogSink,
      rootsSupport: self is RootsSupport ? self : null,
      samplingSupport: self is SamplingSupport ? self : null,
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
  /// The version of the protocol that was negotiated during intialization.
  ///
  /// Some APIs may error if you attempt to use them without first checking the
  /// protocol version.
  late ProtocolVersion protocolVersion;

  /// The [ServerImplementation] returned from the [initialize] request.
  ///
  /// Only assigned after [initialize] has successfully completed.
  late ServerImplementation serverInfo;

  /// The [ServerCapabilities] returned from the [initialize] request.
  ///
  /// Only assigned after [initialize] has successfully completed.
  late ServerCapabilities serverCapabilities;

  /// Emits an event any time the server notifies us of a change to the list of
  /// prompts it supports.
  ///
  /// This is a broadcast stream, events are not buffered and only future events
  /// are given.
  Stream<PromptListChangedNotification> get promptListChanged =>
      _promptListChangedController.stream;
  final _promptListChangedController =
      StreamController<PromptListChangedNotification>.broadcast();

  /// Emits an event any time the server notifies us of a change to the list of
  /// tools it supports.
  ///
  /// This is a broadcast stream, events are not buffered and only future events
  /// are given.
  Stream<ToolListChangedNotification> get toolListChanged =>
      _toolListChangedController.stream;
  final _toolListChangedController =
      StreamController<ToolListChangedNotification>.broadcast();

  /// Emits an event any time the server notifies us of a change to the list of
  /// resources it supports.
  ///
  /// This is a broadcast stream, events are not buffered and only future events
  /// are given.
  Stream<ResourceListChangedNotification> get resourceListChanged =>
      _resourceListChangedController.stream;
  final _resourceListChangedController =
      StreamController<ResourceListChangedNotification>.broadcast();

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

  /// Completes when [shutdown] is called.
  Future<void> get done => _done.future;
  final Completer<void> _done = Completer<void>();

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
  }) {
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
            samplingSupport.handleCreateMessage(request, serverInfo),
      );
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
    _done.complete();
  }

  /// Called after a successful call to [initialize].
  void notifyInitialized(InitializedNotification notification) =>
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
    if (serverVersion?.isSupported != true) {
      await shutdown();
    }
    return response;
  }

  /// List all the tools from this server.
  Future<ListToolsResult> listTools([ListToolsRequest? request]) =>
      sendRequest(ListToolsRequest.methodName, request);

  /// Invokes a [Tool] returned from the [ListToolsResult].
  Future<CallToolResult> callTool(CallToolRequest request) =>
      sendRequest(CallToolRequest.methodName, request);

  /// Lists all the [Resource]s from this server.
  Future<ListResourcesResult> listResources(ListResourcesRequest request) =>
      sendRequest(ListResourcesRequest.methodName, request);

  /// Reads a [Resource] returned from the [ListResourcesResult] or matching
  /// a [ResourceTemplate] from a [ListResourceTemplatesResult].
  Future<ReadResourceResult> readResource(ReadResourceRequest request) =>
      sendRequest(ReadResourceRequest.methodName, request);

  /// Lists all the [ResourceTemplate]s from this server.
  Future<ListResourceTemplatesResult> listResourceTemplates(
    ListResourceTemplatesRequest request,
  ) => sendRequest(ListResourceTemplatesRequest.methodName, request);

  /// Lists all the prompts from this server.
  Future<ListPromptsResult> listPrompts(ListPromptsRequest request) =>
      sendRequest(ListPromptsRequest.methodName, request);

  /// Gets the requested [Prompt] from the server.
  Future<GetPromptResult> getPrompt(GetPromptRequest request) =>
      sendRequest(GetPromptRequest.methodName, request);

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
