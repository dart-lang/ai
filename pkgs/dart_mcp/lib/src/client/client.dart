// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
// TODO: Refactor to drop this dependency?
import 'dart:io';

import 'package:async/async.dart' hide Result;
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:stream_channel/stream_channel.dart';

import '../api.dart';
import '../util.dart';

/// Base class for MCP clients to extend.
abstract base class MCPClient {
  ClientCapabilities get capabilities;
  ClientImplementation get implementation;

  final Map<String, ServerConnection> _connections = {};

  /// Connect to a new MCP server with [name], by invoking [command] with
  /// [arguments] and talking to that process over stdin/stdout.
  Future<ServerConnection> connectStdioServer(
    String name,
    String command,
    List<String> arguments,
  ) async {
    var process = await Process.start(command, arguments);
    var channel = StreamChannel.withCloseGuarantee(
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
    return connectServer(name, channel);
  }

  /// Returns a connection for an MCP server with [name], communicating over
  /// [channel], which is already established.
  ServerConnection connectServer(String name, StreamChannel<String> channel) {
    var connection = ServerConnection.fromStreamChannel(channel);
    _connections[name] = connection;
    return connection;
  }

  /// Shuts down a server connection by [name].
  Future<void> shutdownServer(String name) {
    var server = _connections.remove(name);
    if (server == null) {
      throw ArgumentError('No server with name $name');
    }
    return server.shutdown();
  }

  /// Shuts down all active server connections.
  Future<void> shutdown() async {
    final connections = _connections.values.toList();
    _connections.clear();
    await Future.wait([
      for (var connection in connections) connection.shutdown(),
    ]);
  }
}

/// An active server connection.
class ServerConnection {
  final Peer _peer;

  /// Progress controllers by token.
  ///
  /// These are created through the [onProgress] method.
  final _progressControllers =
      <ProgressToken, StreamController<ProgressNotification>>{};

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

  ServerConnection.fromStreamChannel(StreamChannel<String> channel)
    : _peer = Peer(channel) {
    _peer.registerMethod(PingRequest.methodName, convertParameters(handlePing));

    _peer.registerMethod(
      ProgressNotification.methodName,
      convertParameters(handleProgress),
    );

    _peer.registerMethod(
      PromptListChangedNotification.methodName,
      convertParameters(_promptListChangedController.sink.add),
    );

    _peer.registerMethod(
      ToolListChangedNotification.methodName,
      convertParameters(_toolListChangedController.sink.add),
    );

    _peer.registerMethod(
      ResourceListChangedNotification.methodName,
      convertParameters(_resourceListChangedController.sink.add),
    );

    _peer.registerMethod(
      ResourceUpdatedNotification.methodName,
      convertParameters(_resourceUpdatedController.sink.add),
    );

    _peer.listen();
  }

  /// Close all connections and streams so the process can cleanly exit.
  Future<void> shutdown() async {
    await Future.wait([
      _peer.close(),
      _promptListChangedController.close(),
      _toolListChangedController.close(),
      _resourceListChangedController.close(),
      _resourceUpdatedController.close(),
    ]);
  }

  /// Called after a successful call to [initialize].
  void notifyInitialized(InitializedNotification notification) {
    _peer.sendNotification(InitializedNotification.methodName, notification);
  }

  /// Initializes the server, this should be done before anything else.
  ///
  /// The client must call [notifyInitialized] after receiving and accepting
  /// this response.
  Future<InitializeResult> initialize(InitializeRequest request) =>
      _sendRequest(InitializeRequest.methodName, request);

  /// Pings the server, and returns whether or not it responded within
  /// [timeout].
  ///
  /// The returned future completes after one of the following:
  ///
  ///   - The server responds (returns `true`).
  ///   - The [timeout] is exceeded (returns `false`).
  ///
  /// If the timeout is reached, future values or errors from the ping request
  /// are ignored.
  Future<bool> ping(
    PingRequest request, {
    Duration timeout = const Duration(seconds: 1),
  }) => _sendRequest<EmptyResult>(
    PingRequest.methodName,
    request,
  ).then((_) => true).timeout(timeout, onTimeout: () => false);

  /// The server may ping us at any time, and we should respond with an empty
  /// response.
  FutureOr<EmptyResult> handlePing(PingRequest request) => EmptyResult();

  /// Handles [ProgressNotification]s and forwards them to the streams returned
  /// by [onProgress] calls.
  void handleProgress(ProgressNotification notification) =>
      _progressControllers[notification.progressToken]?.add(notification);

  /// A stream of progress notifications for a given [request].
  ///
  /// The [request] must contain a [ProgressToken] in its metadata (at
  /// `request.meta.progressToken`), otherwise an [ArgumentError] will be
  /// thrown.
  ///
  /// The returned stream is a "broadcast" stream, so events are not buffered
  /// and previous events will not be re-played when you subscribe.
  Stream<ProgressNotification> onProgress(Request request) {
    final token = request.meta?.progressToken;
    if (token == null) {
      throw ArgumentError.value(
        null,
        'request.meta.progressToken',
        'A progress token is required in order to track progress for a request',
      );
    }
    return (_progressControllers[token] ??=
            StreamController<ProgressNotification>.broadcast())
        .stream;
  }

  /// Notifies the server of progress towards completing some request.
  void notifyProgress(ProgressNotification notification) =>
      _peer.sendNotification(ProgressNotification.methodName, notification);

  /// Sends [request] to the server, and handles coercing the response to the
  /// type [T].
  ///
  /// Closes any progress streams for [request] once the response has been
  /// received.
  Future<T> _sendRequest<T extends Result>(
    String methodName,
    Request request,
  ) async {
    try {
      return (await _peer.sendRequest(methodName, request) as Map)
              .cast<String, Object?>()
          as T;
    } finally {
      final token = request.meta?.progressToken;
      if (token != null) {
        await _progressControllers.remove(token)?.close();
      }
    }
  }

  /// List all the tools from this server.
  Future<ListToolsResult> listTools(ListToolsRequest request) =>
      _sendRequest(ListToolsRequest.methodName, request);

  /// Invokes a [Tool] returned from the [ListToolsResult].
  Future<CallToolResult> callTool(CallToolRequest request) =>
      _sendRequest(CallToolRequest.methodName, request);

  /// Lists all the resources from this server.
  Future<ListResourcesResult> listResources(ListResourcesRequest request) =>
      _sendRequest(ListResourcesRequest.methodName, request);

  /// Reads a [Resource] returned from the [ListResourcesResult].
  Future<ReadResourceResult> readResource(ReadResourceRequest request) =>
      _sendRequest(ReadResourceRequest.methodName, request);

  /// Lists all the prompts from this server.
  Future<ListPromptsResult> listPrompts(ListPromptsRequest request) =>
      _sendRequest(ListPromptsRequest.methodName, request);

  /// Gets the requested [Prompt] from the server.
  Future<GetPromptResult> getPrompt(GetPromptRequest request) =>
      _sendRequest(GetPromptRequest.methodName, request);

  /// Subscribes this client to a resource by URI (at `request.uri`).
  ///
  /// Updates will come on the [resourceUpdated] stream.
  void subscribeResource(SubscribeRequest request) =>
      _peer.sendNotification(SubscribeRequest.methodName, request);

  /// Unsubscribes this client to a resource by URI (at `request.uri`).
  ///
  /// Updates will come on the [resourceUpdated] stream.
  void unsubscribeResource(UnsubscribeRequest request) =>
      _peer.sendNotification(UnsubscribeRequest.methodName, request);
}
