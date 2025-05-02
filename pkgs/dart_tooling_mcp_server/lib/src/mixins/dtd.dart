// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:dart_mcp/server.dart';
import 'package:dds_service_extensions/dds_service_extensions.dart';
import 'package:dtd/dtd.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:meta/meta.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import '../utils/constants.dart';

/// Mix this in to any MCPServer to add support for connecting to the Dart
/// Tooling Daemon and all of its associated functionality (see
/// https://pub.dev/packages/dtd).
///
/// The MCPServer must already have the [ToolsSupport] mixin applied.
base mixin DartToolingDaemonSupport
    on ToolsSupport, LoggingSupport, ResourcesSupport {
  DartToolingDaemon? _dtd;

  /// Whether or not the DTD extension to get the active debug sessions is
  /// ready to be invoked.
  bool _getDebugSessionsReady = false;

  /// A Map of [VmService] object [Future]s by their associated
  /// [DebugSession.id].
  ///
  /// [VmService] objects are automatically removed from the Map when the
  /// [DebugSession] shuts down.
  @visibleForTesting
  final activeVmServices = <String, Future<VmService>>{};

  /// Whether to await the disposal of all [VmService] objects in
  /// [activeVmServices] upon server shutdown or loss of DTD connection.
  ///
  /// Defaults to false but can be flipped to true for testing purposes.
  @visibleForTesting
  static bool debugAwaitVmServiceDisposal = false;

  /// The id for the object group used when calling Flutter Widget
  /// Inspector service extensions from DTD tools.
  @visibleForTesting
  static const inspectorObjectGroup = 'dart-tooling-mcp-server';

  /// The prefix for Flutter Widget Inspector service extensions.
  ///
  /// See https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/widgets/service_extensions.dart#L126
  /// for full list of available Flutter Widget Inspector service extensions.
  static const _inspectorServiceExtensionPrefix = 'ext.flutter.inspector';

  /// Called when the DTD connection is lost, resets all associated state.
  Future<void> _resetDtd() async {
    _dtd = null;
    _getDebugSessionsReady = false;

    // TODO: determine whether we need to dispose the [inspectorObjectGroup] on
    // the Flutter Widget Inspector for each VM service instance.

    final future = Future.wait(
      activeVmServices.values.map(
        (vmService) => vmService.then((service) => service.dispose()),
      ),
    );
    debugAwaitVmServiceDisposal ? await future : unawaited(future);

    activeVmServices.clear();
  }

  @visibleForTesting
  Future<void> updateActiveVmServices() async {
    final dtd = _dtd;
    if (dtd == null) return;

    // TODO: in the future, get the active VM service URIs from DTD directly
    // instead of from the `Editor.getDebugSessions` service method.
    if (!_getDebugSessionsReady) {
      // Give it a chance to get ready.
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!_getDebugSessionsReady) return;
    }

    final response = await dtd.getDebugSessions();
    final debugSessions = response.debugSessions;
    for (final debugSession in debugSessions) {
      if (activeVmServices.containsKey(debugSession.id)) {
        continue;
      }
      if (debugSession.vmServiceUri case final vmServiceUri?) {
        final vmService =
            await (activeVmServices[debugSession.id] = vmServiceConnectUri(
              vmServiceUri,
            ));
        // Start listening for and collecting errors immediately.
        final errorService = await _AppErrorsListener.forVmService(vmService);
        final resource = Resource(
          uri: '$runtimeErrorsScheme://${debugSession.id}',
          name: debugSession.name,
        );
        addResource(resource, (request) async {
          final errors = errorService.errors;
          return ReadResourceResult(
            contents: [
              for (var error in errors)
                TextResourceContents(uri: resource.uri, text: error),
            ],
          );
        });
        errorService.errorsStream.listen((_) => updateResource(resource));
        unawaited(
          vmService.onDone.then((_) {
            removeResource(resource.uri);
            activeVmServices.remove(debugSession.id);
          }),
        );
      }
    }
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
    registerTool(getWidgetTreeTool, widgetTree);
    registerTool(getSelectedWidgetTool, selectedWidget);

    return super.initialize(request);
  }

  @override
  Future<void> shutdown() async {
    await _resetDtd();
    await super.shutdown();
  }

  /// Connects to the Dart Tooling Daemon.
  FutureOr<CallToolResult> _connect(CallToolRequest request) async {
    if (_dtd != null) {
      return _dtdAlreadyConnected;
    }

    if (request.arguments?[ParameterNames.uri] == null) {
      return CallToolResult(
        isError: true,
        content: [
          TextContent(text: 'Required parameter "uri" was not provided.'),
        ],
      );
    }

    try {
      _dtd = await DartToolingDaemon.connect(
        Uri.parse(request.arguments![ParameterNames.uri] as String),
      );
      unawaited(_dtd!.done.then((_) async => await _resetDtd()));

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
      log(
        LoggingLevel.debug,
        () => 'DTD Service event:\n${e.kind}: ${jsonEncode(e.data)}',
      );
      switch (e.kind) {
        case 'ServiceRegistered':
          if (e.data['service'] == 'Editor' &&
              e.data['method'] == 'getDebugSessions') {
            log(
              LoggingLevel.debug,
              'Editor.getDebugSessions registered, dtd is ready',
            );
            _getDebugSessionsReady = true;
          }
        case 'ServiceUnregistered':
          if (e.data['service'] == 'Editor' &&
              e.data['method'] == 'getDebugSessions') {
            log(
              LoggingLevel.debug,
              'Editor.getDebugSessions unregistered, dtd is no longer ready',
            );
            _getDebugSessionsReady = false;
          }
      }
    });
    dtd.streamListen('Service');

    dtd.onEvent('Editor').listen((e) async {
      log(LoggingLevel.debug, e.toString());
      switch (e.kind) {
        case 'debugSessionStarted':
        case 'debugSessionChanged':
          await updateActiveVmServices();
        case 'debugSessionStopped':
          await activeVmServices
              .remove((e.data['debugSession'] as DebugSession).id)
              ?.then((service) => service.dispose());
        default:
      }
    });
    dtd.streamListen('Editor');
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
        if (request.arguments?['clearRuntimeErrors'] == true) {
          (await _AppErrorsListener.forVmService(vmService)).errors.clear();
        }

        StreamSubscription<Event>? serviceStreamSubscription;
        try {
          final hotReloadMethodNameCompleter = Completer<String?>();
          serviceStreamSubscription = vmService
              .onEvent(EventStreams.kService)
              .listen((Event e) {
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
          if (hotReloadMethodName == null) {
            return CallToolResult(
              isError: true,
              content: [
                TextContent(
                  text:
                      'The hot reload service has not been registered yet. '
                      'Please wait a few seconds and try again.',
                ),
              ],
            );
          }

          final vm = await vmService.getVM();
          final result = await vmService.callMethod(
            hotReloadMethodName,
            isolateId: vm.isolates!.first.id,
          );
          final resultType = result.json?['type'];
          if (resultType == 'Success' ||
              (resultType == 'ReloadReport' &&
                  result.json?['success'] == true)) {
            return CallToolResult(
              content: [TextContent(text: 'Hot reload succeeded.')],
            );
          } else {
            return CallToolResult(
              isError: true,
              content: [
                TextContent(text: 'Hot reload failed:\n${result.json}'),
              ],
            );
          }
        } finally {
          await serviceStreamSubscription?.cancel();
          await vmService.streamCancel(EventStreams.kService);
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
        try {
          final errorService = await _AppErrorsListener.forVmService(vmService);
          final errors = errorService.errors;

          if (errors.isEmpty) {
            return CallToolResult(
              content: [TextContent(text: 'No runtime errors found.')],
            );
          }
          final result = CallToolResult(
            content: [
              TextContent(
                text:
                    'Found ${errors.length} '
                    'error${errors.length == 1 ? '' : 's'}:\n',
              ),
              ...errors.map((e) => TextContent(text: e.toString())),
            ],
          );
          if (request.arguments?['clearRuntimeErrors'] == true) {
            errorService.errors.clear();
          }
          return result;
        } catch (e) {
          return CallToolResult(
            isError: true,
            content: [TextContent(text: 'Failed to get runtime errors: $e')],
          );
        }
      },
    );
  }

  /// Retrieves the Flutter widget tree from the currently running app.
  ///
  /// If more than one debug session is active, then it just uses the first one.
  ///
  // TODO: support passing a debug session id when there is more than one debug
  // session.
  Future<CallToolResult> widgetTree(CallToolRequest request) async {
    return _callOnVmService(
      callback: (vmService) async {
        final vm = await vmService.getVM();
        final isolateId = vm.isolates!.first.id;
        try {
          final result = await vmService.callServiceExtension(
            '$_inspectorServiceExtensionPrefix.getRootWidgetTree',
            isolateId: isolateId,
            args: {
              'groupName': inspectorObjectGroup,
              // TODO: consider making these configurable or using defaults that
              // are better for the LLM.
              'isSummaryTree': 'true',
              'withPreviews': 'true',
              'fullDetails': 'false',
            },
          );
          final tree = result.json?['result'];
          if (tree == null) {
            return CallToolResult(
              content: [
                TextContent(
                  text:
                      'Could not get Widget tree. '
                      'Unexpected result: ${result.json}.',
                ),
              ],
            );
          }
          return CallToolResult(content: [TextContent(text: jsonEncode(tree))]);
        } catch (e) {
          return CallToolResult(
            isError: true,
            content: [
              TextContent(
                text: 'Unknown error or bad response getting widget tree:\n$e',
              ),
            ],
          );
        }
      },
    );
  }

  /// Retrieves the selected widget from the currently running app.
  ///
  /// If more than one debug session is active, then it just uses the first one.
  // TODO: support passing a debug session id when there is more than one debug
  // session.
  Future<CallToolResult> selectedWidget(CallToolRequest request) async {
    return _callOnVmService(
      callback: (vmService) async {
        final vm = await vmService.getVM();
        final isolateId = vm.isolates!.first.id;
        try {
          final result = await vmService.callServiceExtension(
            '$_inspectorServiceExtensionPrefix.getSelectedSummaryWidget',
            isolateId: isolateId,
            args: {'objectGroup': inspectorObjectGroup},
          );

          final widget = result.json?['result'];
          if (widget == null) {
            return CallToolResult(
              content: [TextContent(text: 'No Widget selected.')],
            );
          }
          return CallToolResult(
            content: [TextContent(text: jsonEncode(widget))],
          );
        } catch (e) {
          return CallToolResult(
            isError: true,
            content: [TextContent(text: 'Failed to get selected widget: $e')],
          );
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

    await updateActiveVmServices();
    if (activeVmServices.isEmpty) return _noActiveDebugSession;

    // TODO: support selecting a VM Service if more than one are available.
    final vmService = activeVmServices.values.first;
    return await callback(await vmService);
  }

  @visibleForTesting
  static final connectTool = Tool(
    name: 'connect_dart_tooling_daemon',
    description:
        'Connects to the Dart Tooling Daemon. You should ask the user for the '
        'dart tooling daemon URI, and suggest the "Copy DTD Uri to clipboard" '
        'command. Do not just make up a random URI to pass.',
    annotations: ToolAnnotations(title: 'Connect to DTD', readOnlyHint: true),
    inputSchema: Schema.object(
      properties: {ParameterNames.uri: Schema.string()},
      required: const [ParameterNames.uri],
    ),
  );

  @visibleForTesting
  static final getRuntimeErrorsTool = Tool(
    name: 'get_runtime_errors',
    description:
        'Retrieves the list of runtime errors that have occurred in the active '
        'Dart or Flutter application. Requires "${connectTool.name}" to be '
        'successfully called first.',
    annotations: ToolAnnotations(
      title: 'Get runtime errors',
      readOnlyHint: true,
    ),
    inputSchema: Schema.object(
      properties: {
        'clearRuntimeErrors': Schema.bool(
          title: 'Whether to clear the runtime errors after retrieving them.',
          description:
              'This is useful to clear out old errors that may no longer be '
              'relevant before reading them again.',
        ),
      },
    ),
  );

  @visibleForTesting
  static final screenshotTool = Tool(
    name: 'take_screenshot',
    description:
        'Takes a screenshot of the active Flutter application in its '
        'current state. Requires "${connectTool.name}" to be successfully '
        'called first.',
    annotations: ToolAnnotations(title: 'Take screenshot', readOnlyHint: true),
    inputSchema: Schema.object(),
  );

  @visibleForTesting
  static final hotReloadTool = Tool(
    name: 'hot_reload',
    description:
        'Performs a hot reload of the active Flutter application. '
        'This is to apply the latest code changes to the running application. '
        'Requires "${connectTool.name}" to be successfully called first.',
    annotations: ToolAnnotations(title: 'Hot reload', destructiveHint: true),
    inputSchema: Schema.object(
      properties: {
        'clearRuntimeErrors': Schema.bool(
          title: 'Whether to clear runtime errors before hot reloading.',
          description:
              'This is useful to clear out old errors that may no longer be '
              'relevant.',
        ),
      },
      required: [],
    ),
  );

  @visibleForTesting
  static final getWidgetTreeTool = Tool(
    name: 'get_widget_tree',
    description:
        'Retrieves the widget tree from the active Flutter application. '
        'Requires "${connectTool.name}" to be successfully called first.',
    annotations: ToolAnnotations(title: 'Get widget tree', readOnlyHint: true),
    inputSchema: Schema.object(),
  );

  @visibleForTesting
  static final getSelectedWidgetTool = Tool(
    name: 'get_selected_widget',
    description:
        'Retrieves the selected widget from the active Flutter application. '
        'Requires "${connectTool.name}" to be successfully called first.',
    annotations: ToolAnnotations(
      title: 'Get selected widget',
      readOnlyHint: true,
    ),
    inputSchema: Schema.object(),
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

  static final runtimeErrorsScheme = 'runtime-errors';
}

/// Listens on a VM service for errors.
class _AppErrorsListener {
  /// All the errors recorded so far (may be cleared explicitly).
  final List<String> errors;

  /// A broadcast stream of all errors that come in after you start listening.
  Stream<String> get errorsStream => _errorsController.stream;

  /// Controller for the [errorsStream].
  final StreamController<String> _errorsController;

  /// The listener for Flutter.Error vm service extension events.
  final StreamSubscription<Event> _extensionEventsListener;

  /// The stderr listener on the flutter process.
  final StreamSubscription<Event> _stderrEventsListener;

  /// The vm service instance connected to the flutter app.
  final VmService _vmService;

  _AppErrorsListener._(
    this.errors,
    this._errorsController,
    this._extensionEventsListener,
    this._stderrEventsListener,
    this._vmService,
  ) {
    _vmService.onDone.then((_) => shutdown());
  }

  /// Maintain a cache of error listeners by [VmService] instance as an
  /// [Expando] so we don't have to worry about explicit cleanup.
  static final _errorListeners = Expando<_AppErrorsListener>();

  /// Returns the canonical [_AppErrorsListener] for the [vmService] instance,
  /// which may be an already existing instance.
  static Future<_AppErrorsListener> forVmService(VmService vmService) async {
    return _errorListeners[vmService] ??= await () async {
      // Needs to be a broadcast stream because we use it to add errors to the
      // list but also expose it to clients so they can know when new errors
      // are added.
      final errorsController = StreamController<String>.broadcast();
      final errors = <String>[];
      errorsController.stream.listen(errors.add);
      // We need to listen to streams with history so that we can get errors
      // that occurred before this tool call.
      // TODO(https://github.com/dart-lang/ai/issues/57): this can result in
      // duplicate errors that we need to de-duplicate somehow.
      final extensionEvents = vmService.onExtensionEventWithHistory.listen((
        Event e,
      ) {
        if (e.extensionKind == 'Flutter.Error') {
          // TODO(https://github.com/dart-lang/ai/issues/57): consider
          // pruning this content down to only what is useful for the LLM to
          // understand the error and its source.
          errorsController.add(e.json.toString());
        }
      });
      final stderrEvents = vmService.onStderrEventWithHistory.listen((Event e) {
        final message = decodeBase64(e.bytes!);
        // TODO(https://github.com/dart-lang/ai/issues/57): consider
        // pruning this content down to only what is useful for the LLM to
        // understand the error and its source.
        errorsController.add(message);
      });

      await vmService.streamListen(EventStreams.kExtension);
      await vmService.streamListen(EventStreams.kStderr);
      return _AppErrorsListener._(
        errors,
        errorsController,
        extensionEvents,
        stderrEvents,
        vmService,
      );
    }();
  }

  Future<void> shutdown() async {
    errors.clear();
    await _errorsController.close();
    await _extensionEventsListener.cancel();
    await _stderrEventsListener.cancel();
    try {
      await _vmService.streamCancel(EventStreams.kExtension);
      await _vmService.streamCancel(EventStreams.kStderr);
    } on RPCError catch (_) {
      // The vm service might already be disposed in which causes these to fail.
    }
  }
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
  String? get vmServiceUri => _value['vmServiceUri'] as String?;

  factory DebugSession({
    required String debuggerType,
    required String id,
    required String name,
    required String projectRootPath,
    required String? vmServiceUri,
  }) => DebugSession.fromJson({
    'debuggerType': debuggerType,
    'id': id,
    'name': name,
    'projectRootPath': projectRootPath,
    if (vmServiceUri != null) 'vmServiceUri': vmServiceUri,
  });
}
