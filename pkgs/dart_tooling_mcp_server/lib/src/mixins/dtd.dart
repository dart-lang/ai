// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/server.dart';
import 'package:dds_service_extensions/dds_service_extensions.dart';
import 'package:dtd/dtd.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:meta/meta.dart';
import 'package:vm_service/vm_service.dart';
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
    registerTool(connectTool, _connect);
    registerTool(getRuntimeErrorsTool, runtimeErrors);

    // TODO: these tools should only be registered for Flutter applications, or
    // they should return an error when used against a pure Dart app (or a
    // Flutter app that does not support the operation, e.g. hot reload is not
    // supported in profile mode).
    registerTool(screenshotTool, takeScreenshot);
    registerTool(hotReloadTool, hotReload);

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
    return _callOnVmService(
      callback: (vmService) async {
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
                text:
                    'Unknown error or bad response taking screenshot:\n'
                    '${result.json}',
              ),
            ],
          );
        }
      },
    );
  }

  /// Performs a hot reload on the currently running app.
  ///
  /// If more than one debug session is active, then it just uses the first one.
  ///
  // TODO: support passing a debug session id when there is more than one debug
  // session.
  Future<CallToolResult> hotReload(CallToolRequest request) async {
    return _callOnVmService(
      callback: (vmService) async {
        final vm = await vmService.getVM();

        final hotReloadMethodNameCompleter = Completer<String?>();
        vmService.onEvent(EventStreams.kService).listen((Event e) {
          if (e.kind == EventKind.kServiceRegistered) {
            final serviceName = e.service!;
            if (serviceName == 'reloadSources') {
              // This may look something like 's0.reloadSources'.
              hotReloadMethodNameCompleter.complete(e.method);
            }
          }
        });
        await vmService.streamListen(EventStreams.kService);
        final hotReloadMethodName = await hotReloadMethodNameCompleter.future
            .timeout(
              const Duration(milliseconds: 1000),
              onTimeout: () async {
                return null;
              },
            );
        await vmService.streamCancel(EventStreams.kService);

        if (hotReloadMethodName == null) {
          return CallToolResult(
            isError: true,
            content: [
              TextContent(
                text:
                    'The hot reload service has not been registered yet, '
                    'please wait a few seconds and try again.',
              ),
            ],
          );
        }

        final result = await vmService.callMethod(
          hotReloadMethodName,
          isolateId: vm.isolates!.first.id,
        );
        final resultType = result.json?['type'];
        if (resultType == 'Success' ||
            (resultType == 'ReloadReport' && result.json?['success'] == true)) {
          return CallToolResult(
            content: [TextContent(text: 'Hot reload succeeded.')],
          );
        } else {
          return CallToolResult(
            isError: true,
            content: [
              TextContent(
                text:
                    'Hot reload failed:\n'
                    '${result.json}',
              ),
            ],
          );
        }
      },
    );
  }

  /// Retrieves runtime errors from the currently running app.
  ///
  /// If more than one debug session is active, then it just uses the first one.
  ///
  // TODO: support passing a debug session id when there is more than one debug
  // session.
  Future<CallToolResult> runtimeErrors(CallToolRequest request) async {
    return _callOnVmService(
      callback: (vmService) async {
        final errors = <String>[];
        StreamSubscription<Event>? extensionEvents;
        StreamSubscription<Event>? stderrEvents;
        try {
          // We need to listen to streams with history so that we can get errors
          // that occurred before this tool call.
          // TODO(https://github.com/dart-lang/ai/issues/57): this can result in
          // duplicate errors that we need to de-duplicate somehow.
          extensionEvents = vmService.onExtensionEventWithHistory.listen((
            Event e,
          ) {
            if (e.extensionKind == 'Flutter.Error') {
              // TODO(https://github.com/dart-lang/ai/issues/57): consider
              // pruning this content down to only what is useful for the LLM to
              // understand the error and its source.
              errors.add(e.json.toString());
            }
          });
          stderrEvents = vmService.onStderrEventWithHistory.listen((Event e) {
            final message = decodeBase64(e.bytes!);
            // TODO(https://github.com/dart-lang/ai/issues/57): consider
            // pruning this content down to only what is useful for the LLM to
            // understand the error and its source.
            errors.add(message);
          });

          await vmService.streamListen(EventStreams.kExtension);
          await vmService.streamListen(EventStreams.kStderr);

          // Await a short delay to allow the error events to come over the open
          // Streams.
          await Future<void>.delayed(const Duration(seconds: 1));

          if (errors.isEmpty) {
            return CallToolResult(
              content: [TextContent(text: 'No runtime errors found.')],
            );
          }
          return CallToolResult(
            content: [
              TextContent(
                text:
                    'Found ${errors.length} '
                    'error${errors.length == 1 ? '' : 's'}:\n',
              ),
              ...errors.map((e) => TextContent(text: e.toString())),
            ],
          );
        } catch (e) {
          return CallToolResult(
            isError: true,
            content: [TextContent(text: 'Failed to get runtime errors: $e')],
          );
        } finally {
          await extensionEvents?.cancel();
          await stderrEvents?.cancel();
          await vmService.streamCancel(EventStreams.kExtension);
          await vmService.streamCancel(EventStreams.kStderr);
        }
      },
    );
  }

  /// Calls [callback] on the first active debug session, if available.
  Future<CallToolResult> _callOnVmService({
    required Future<CallToolResult> Function(VmService) callback,
  }) async {
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
      return await callback(vmService);
    } finally {
      unawaited(vmService.dispose());
    }
  }

  @visibleForTesting
  static final connectTool = Tool(
    inputSchema: ObjectSchema(
      properties: {'uri': StringSchema()},
      required: const ['uri'],
    ),
    name: 'connect_dart_tooling_daemon',
    description:
        'Connects to the Dart Tooling Daemon. You should ask the user for the '
        'dart tooling daemon URI, and suggest the "Copy DTD Uri to clipboard" '
        'command. Do not just make up a random URI to pass.',
  );

  @visibleForTesting
  static final screenshotTool = Tool(
    name: 'take_screenshot',
    description:
        'Takes a screenshot of the active Flutter application in its '
        'current state. Requires "${connectTool.name}" to be successfully '
        'called first.',
    inputSchema: ObjectSchema(),
  );

  @visibleForTesting
  static final hotReloadTool = Tool(
    name: 'hot_reload',
    description:
        'Performs a hot reload of the active Flutter application. '
        'This is to apply the latest code changes to the running application. '
        'Requires "${connectTool.name}" to be successfully called first.',
    inputSchema: ObjectSchema(),
  );

  @visibleForTesting
  static final getRuntimeErrorsTool = Tool(
    name: 'get_runtime_errors',
    description:
        'Retrieves the list of runtime errors that have occurred in the active '
        'Dart or Flutter application. Requires "${connectTool.name}" to be '
        'successfully called first.',
    inputSchema: ObjectSchema(),
  );

  static final _dtdNotConnected = CallToolResult(
    isError: true,
    content: [
      TextContent(
        text:
            'The dart tooling daemon is not connected, you need to call '
            '"${connectTool.name}" first.',
      ),
    ],
  );

  static final _dtdAlreadyConnected = CallToolResult(
    isError: true,
    content: [
      TextContent(
        text:
            'The dart tooling daemon is already connected, you cannot call '
            '"${connectTool.name}" again.',
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
        text:
            'The dart tooling daemon is not ready yet, please wait a few '
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
  }) => GetDebugSessionsResponse.fromJson({
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
  }) => DebugSession.fromJson({
    'debuggerType': debuggerType,
    'id': id,
    'name': name,
    'projectRootPath': projectRootPath,
    'vmServiceUri': vmServiceUri,
  });
}
