// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/server.dart';
import 'package:dtd/dtd.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:vm_service/vm_service_io.dart';

/// Mix this in to any MCPServer to add support for connecting to the Dart
/// Tooling Daemon and all of its associated functionality (see
/// https://pub.dev/packages/dtd).
///
/// The MCPServer must already have the [ToolsSupport] mixin applied.
base mixin DartToolingDaemonSupport on ToolsSupport {
  DartToolingDaemon? _dtd;

  /// Whether or not the DTD extension to get the active debug sessions is
  /// ready to be invoked.
  bool _getDebugSessionsReady = false;

  /// Called when the DTD connection is lost, resets all associated state.
  void _resetDtd() {
    _dtd = null;
    _getDebugSessionsReady = false;
  }

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) async {
    registerTool(_connectTool, _connect);
    registerTool(_screenshotTool, takeScreenshot);
    return super.initialize(request);
  }

  /// Connects to the Dart Tooling Daemon.
  FutureOr<CallToolResult> _connect(CallToolRequest request) async {
    if (_dtd != null) {
      return _dtdAlreadyConnected;
    }

    if (request.arguments?['uri'] == null) {
      return CallToolResult(
        isError: true,
        content: [
          TextContent(text: 'Required parameter "uri" was not provided.'),
        ],
      );
    }

    try {
      _dtd = await DartToolingDaemon.connect(
        Uri.parse(request.arguments!['uri'] as String),
      );
      unawaited(_dtd!.done.then((_) => _resetDtd()));

      _listenForServices();
      return CallToolResult(
        content: [TextContent(text: 'Connection succeeded')],
      );
    } catch (e) {
      return CallToolResult(
        isError: true,
        content: [TextContent(text: 'Connection failed: $e')],
      );
    }
  }

  /// Listens to the `Service` stream so we know when the
  /// `Editor.getDebugSessions` extension method is registered.
  ///
  /// The dart tooling daemon must be connected prior to calling this function.
  void _listenForServices() {
    final dtd = _dtd!;
    dtd.onEvent('Service').listen((e) async {
      switch (e.kind) {
        case 'ServiceRegistered':
          if (e.data['service'] == 'Editor' &&
              e.data['method'] == 'getDebugSessions') {
            _getDebugSessionsReady = true;
          }
        case 'ServiceUnregistered':
          if (e.data['service'] == 'Editor' &&
              e.data['method'] == 'getDebugSessions') {
            _getDebugSessionsReady = false;
          }
      }
    });
    dtd.streamListen('Service');
  }

  /// Takes a screenshot of the currently running app.
  ///
  /// If more than one debug session is active, then it just uses the first one.
  //
  // TODO: support passing a debug session id when there is more than one debug
  // session.
  Future<CallToolResult> takeScreenshot(CallToolRequest request) async {
    final dtd = _dtd;
    if (dtd == null) return _dtdNotConnected;
    if (!_getDebugSessionsReady) {
      // Give it a chance to get ready.
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!_getDebugSessionsReady) return _dtdNotReady;
    }

    final response = await dtd.getDebugSessions();
    final debugSessions = response.debugSessions;
    if (debugSessions.isEmpty) return _noActiveDebugSession;

    // TODO: Consider holding on to this connection.
    final vmService = await vmServiceConnectUri(
      debugSessions.first.vmServiceUri,
    );

    try {
      final vm = await vmService.getVM();
      final result = await vmService.callServiceExtension(
        '_flutter.screenshot',
        isolateId: vm.isolates!.first.id,
      );
      if (result.json?['type'] == 'Screenshot' &&
          result.json?['screenshot'] is String) {
        return CallToolResult(
          content: [
            ImageContent(
              data: result.json!['screenshot'] as String,
              mimeType: 'image/png',
            ),
          ],
        );
      } else {
        return CallToolResult(
          isError: true,
          content: [
            TextContent(
              text: 'Unknown error or bad response taking screenshot:\n'
                  '${result.json}',
            ),
          ],
        );
      }
    } finally {
      unawaited(vmService.dispose());
    }
  }

  static final _connectTool = Tool(
    inputSchema: ObjectSchema(
      properties: {
        'uri': StringSchema(),
      },
      required: const ['uri'],
    ),
    name: 'connectDartToolingDaemon',
    description:
        'Connects to the Dart Tooling Daemon. You should ask the user for the '
        'dart tooling daemon URI, and suggest the "Copy DTD Uri to clipboard" '
        'command. Do not just make up a random URI to pass.',
  );

  static final _screenshotTool = Tool(
    name: 'take_screenshot',
    description: 'Takes a screenshot of the active flutter application in its '
        'current state. Requires "${_connectTool.name}" to be successfully '
        'called first.',
    inputSchema: ObjectSchema(),
  );

  static final _dtdNotConnected = CallToolResult(
    isError: true,
    content: [
      TextContent(
        text: 'The dart tooling daemon is not connected, you need to call '
            '"${_connectTool.name}" first.',
      ),
    ],
  );

  static final _dtdAlreadyConnected = CallToolResult(
    isError: true,
    content: [
      TextContent(
        text: 'The dart tooling daemon is already connected, you cannot call '
            '"${_connectTool.name}" again.',
      ),
    ],
  );

  static final _noActiveDebugSession = CallToolResult(
    content: [
      TextContent(text: 'No active debug session to take a screenshot'),
    ],
    isError: true,
  );

  static final _dtdNotReady = CallToolResult(
    isError: true,
    content: [
      TextContent(
        text: 'The dart tooling daemon is not ready yet, please wait a few '
            'seconds and try again.',
      ),
    ],
  );
}

/// Adds the [getDebugSessions] method to [DartToolingDaemon], so that calling
/// the Editor.getDebugSessions service method can be wrapped nicely behind a
/// method call from a given client.
//
// TODO: Consider moving some of this to a shared location, possible under the
// dtd  package.
extension GetDebugSessions on DartToolingDaemon {
  Future<GetDebugSessionsResponse> getDebugSessions() async {
    final result = await call(
      'Editor',
      'getDebugSessions',
      params: GetDebugSessionsRequest(),
    );
    return GetDebugSessionsResponse.fromDTDResponse(result);
  }
}

/// The request type for the `Editor.getDebugSessions` extension method.
//
// TODO: Consider moving some of this to a shared location, possible under the
// dtd  package.
extension type GetDebugSessionsRequest.fromJson(Map<String, Object?> _value)
    implements Map<String, Object?> {
  factory GetDebugSessionsRequest({bool? verbose}) =>
      GetDebugSessionsRequest.fromJson({
        if (verbose != null) 'verbose': verbose,
      });

  bool? get verbose => _value['verbose'] as bool?;
}

/// The response type for the `Editor.getDebugSessions` extension method.
//
// TODO: Consider moving some of this to a shared location, possible under the
// dtd  package.
extension type GetDebugSessionsResponse.fromJson(Map<String, Object?> _value)
    implements Map<String, Object?> {
  static const String type = 'GetDebugSessionsResult';

  List<DebugSession> get debugSessions =>
      (_value['debugSessions'] as List).cast<DebugSession>();

  factory GetDebugSessionsResponse.fromDTDResponse(DTDResponse response) {
    // Ensure that the response has the type you expect.
    if (response.type != type) {
      throw RpcException.invalidParams(
        'Expected DTDResponse.type to be $type, got: ${response.type}',
      );
    }
    return GetDebugSessionsResponse.fromJson(response.result);
  }

  factory GetDebugSessionsResponse({
    required List<DebugSession> debugSessions,
  }) =>
      GetDebugSessionsResponse.fromJson({
        'debugSessions': debugSessions,
        'type': type,
      });
}

/// An individual debug session.
//
// TODO: Consider moving some of this to a shared location, possible under the
// dtd  package.
extension type DebugSession.fromJson(Map<String, Object?> _value)
    implements Map<String, Object?> {
  String get debuggerType => _value['debuggerType'] as String;
  String get id => _value['id'] as String;
  String get name => _value['name'] as String;
  String get projectRootPath => _value['projectRootPath'] as String;
  String get vmServiceUri => _value['vmServiceUri'] as String;

  factory DebugSession({
    required String debuggerType,
    required String id,
    required String name,
    required String projectRootPath,
    required String vmServiceUri,
  }) =>
      DebugSession.fromJson({
        'debuggerType': debuggerType,
        'id': id,
        'name': name,
        'projectRootPath': projectRootPath,
        'vmServiceUri': vmServiceUri,
      });
}
