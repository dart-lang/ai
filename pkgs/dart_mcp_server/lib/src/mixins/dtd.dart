// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:dart_mcp/server.dart';
import 'package:dds_service_extensions/dds_service_extensions.dart';
import 'package:dtd/dtd.dart';
import 'package:meta/meta.dart';
import 'package:unified_analytics/unified_analytics.dart' as ua;
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';
import 'package:web_socket/web_socket.dart';

import '../utils/analytics.dart';
import '../utils/constants.dart';

/// Mix this in to any MCPServer to add support for connecting to the Dart
/// Tooling Daemon and all of its associated functionality (see
/// https://pub.dev/packages/dtd).
///
/// The MCPServer must already have the [ToolsSupport] mixin applied.
base mixin DartToolingDaemonSupport
    on ToolsSupport, LoggingSupport, ResourcesSupport
    implements AnalyticsSupport {
  DartToolingDaemon? _dtd;

  /// The last reported active location from the editor.
  Map<String, Object?>? _activeLocation;

  /// A Map of [VmService] object [Future]s by their VM Service URI.
  ///
  /// [VmService] objects are automatically removed from the Map when they
  /// are unregistered via DTD or when the VM service shuts down.
  @visibleForTesting
  final activeVmServices = <String, Future<VmService>>{};

  /// Whether or not the connected app service is supported.
  ///
  /// Once we connect to dtd, this may be toggled to `true`.
  bool _connectedAppServiceIsSupported = false;

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

  /// Whether or not to enable the screenshot tool.
  bool get enableScreenshots;

  /// Called when the DTD connection is lost, resets all associated state.
  Future<void> _resetDtd() async {
    _dtd = null;
    _activeLocation = null;
    _connectedAppServiceIsSupported = false;

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
    if (!_connectedAppServiceIsSupported) return;

    final vmServiceInfos = (await dtd.getVmServices()).vmServicesInfos;
    if (vmServiceInfos.isEmpty) return;

    for (final vmServiceInfo in vmServiceInfos) {
      final vmServiceUri = vmServiceInfo.uri;
      if (activeVmServices.containsKey(vmServiceUri)) {
        continue;
      }
      final vmServiceFuture = activeVmServices[vmServiceUri] =
          vmServiceConnectUri(vmServiceUri);
      final vmService = await vmServiceFuture;
      // Start listening for and collecting errors immediately.
      final errorService = await _AppErrorsListener.forVmService(
        vmService,
        this,
      );
      final resource = Resource(
        uri: '$runtimeErrorsScheme://${vmService.id}',
        name: 'Errors for app ${vmServiceInfo.name}',
        description:
            'Recent runtime errors seen for app "${vmServiceInfo.name}".',
      );
      addResource(resource, (request) async {
        final watch = Stopwatch()..start();
        final result = ReadResourceResult(
          contents: [
            for (var error in errorService.errorLog.errors)
              TextResourceContents(uri: resource.uri, text: error),
          ],
        );
        watch.stop();
        try {
          analytics?.send(
            ua.Event.dartMCPEvent(
              client: clientInfo.name,
              clientVersion: clientInfo.version,
              serverVersion: implementation.version,
              type: AnalyticsEvent.readResource.name,
              additionalData: ReadResourceMetrics(
                kind: ResourceKind.runtimeErrors,
                length: result.contents.length,
                elapsedMilliseconds: watch.elapsedMilliseconds,
              ),
            ),
          );
        } catch (e) {
          log(LoggingLevel.warning, 'Error sending analytics event: $e');
        }
        return result;
      });
      try {
        errorService.errorsStream.listen((_) => updateResource(resource));
      } catch (_) {}
      unawaited(
        vmService.onDone.then((_) {
          removeResource(resource.uri);
          activeVmServices.remove(vmServiceUri);
        }),
      );
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
    if (enableScreenshots) registerTool(screenshotTool, takeScreenshot);
    registerTool(hotReloadTool, hotReload);
    registerTool(getWidgetTreeTool, widgetTree);
    registerTool(getSelectedWidgetTool, selectedWidget);
    registerTool(setWidgetSelectionModeTool, _setWidgetSelectionMode);
    registerTool(getActiveLocationTool, _getActiveLocation);

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

    try {
      _dtd = await DartToolingDaemon.connect(
        Uri.parse(request.arguments![ParameterNames.uri] as String),
      );
      unawaited(_dtd!.done.then((_) async => await _resetDtd()));

      await _listenForServices();
      return CallToolResult(
        content: [TextContent(text: 'Connection succeeded')],
      );
    } on WebSocketException catch (_) {
      return CallToolResult(
        isError: true,
        content: [
          Content.text(
            text: 'Connection failed, make sure your DTD Uri is up to date.',
          ),
        ],
      )..failureReason = CallToolFailureReason.webSocketException;
    } catch (e) {
      return CallToolResult(
        isError: true,
        content: [Content.text(text: 'Connection failed: $e')],
      );
    }
  }

  /// Listens to the `ConnectedApp` and `Editor` streams to get app and IDE
  /// state information.
  ///
  /// The dart tooling daemon must be connected prior to calling this function.
  Future<void> _listenForServices() async {
    final dtd = _dtd!;

    _connectedAppServiceIsSupported = false;
    try {
      final registeredServices = await dtd.getRegisteredServices();
      if (registeredServices.dtdServices.contains(
        '${ConnectedAppServiceConstants.serviceName}.'
        '${ConnectedAppServiceConstants.getVmServices}',
      )) {
        _connectedAppServiceIsSupported = true;
      }
    } catch (_) {}

    if (_connectedAppServiceIsSupported) {
      await _listenForConnectedAppServiceEvents();
    }
    await _listenForEditorEvents();
  }

  Future<void> _listenForConnectedAppServiceEvents() async {
    final dtd = _dtd!;
    dtd.onVmServiceUpdate().listen((e) async {
      log(LoggingLevel.debug, e.toString());
      switch (e.kind) {
        case ConnectedAppServiceConstants.vmServiceRegistered:
          await updateActiveVmServices();
        case ConnectedAppServiceConstants.vmServiceUnregistered:
          await activeVmServices
              .remove(e.data['uri'] as String)
              ?.then((service) => service.dispose());
        default:
      }
    });
    await dtd.streamListen(ConnectedAppServiceConstants.serviceName);
  }

  /// Listens for editor specific events.
  Future<void> _listenForEditorEvents() async {
    final dtd = _dtd!;
    dtd.onEvent('Editor').listen((e) async {
      log(LoggingLevel.debug, e.toString());
      switch (e.kind) {
        case 'activeLocationChanged':
          _activeLocation = e.data;
        default:
      }
    });
    await dtd.streamListen('Editor');
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
          (await _AppErrorsListener.forVmService(
            vmService,
            this,
          )).errorLog.clear();
        }

        final vm = await vmService.getVM();
        ReloadReport? report;
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

          /// If we haven't seen a specific one, we just call the default one.
          if (hotReloadMethodName == null) {
            report = await vmService.reloadSources(vm.isolates!.first.id!);
          } else {
            final result = await vmService.callMethod(
              hotReloadMethodName,
              isolateId: vm.isolates!.first.id,
            );
            final resultType = result.json?['type'];
            if (resultType == 'Success' ||
                (resultType == 'ReloadReport' &&
                    result.json?['success'] == true)) {
              report = ReloadReport(success: true);
            } else {
              report = ReloadReport(success: false);
            }
          }
        } finally {
          await serviceStreamSubscription?.cancel();
          await vmService.streamCancel(EventStreams.kService);
        }
        final success = report.success == true;
        return CallToolResult(
          isError: !success ? true : null,
          content: [
            TextContent(
              text: 'Hot reload ${success ? 'succeeded' : 'failed'}.',
            ),
          ],
        );
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
          final errorService = await _AppErrorsListener.forVmService(
            vmService,
            this,
          );
          final errorLog = errorService.errorLog;

          if (errorLog.errors.isEmpty) {
            return CallToolResult(
              content: [TextContent(text: 'No runtime errors found.')],
            );
          }
          final result = CallToolResult(
            content: [
              TextContent(
                text:
                    'Found ${errorLog.errors.length} '
                    'error${errorLog.errors.length == 1 ? '' : 's'}:\n',
              ),
              for (final e in errorLog.errors) TextContent(text: e.toString()),
            ],
          );
          if (request.arguments?['clearRuntimeErrors'] == true) {
            errorService.errorLog.clear();
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

  /// Enables or disables widget selection mode in the currently running app.
  ///
  /// If more than one debug session is active, then it just uses the first one.
  //
  // TODO: support passing a debug session id when there is more than one debug
  // session.
  Future<CallToolResult> _setWidgetSelectionMode(
    CallToolRequest request,
  ) async {
    final enabled = request.arguments?['enabled'] as bool?;
    if (enabled == null) {
      return CallToolResult(
        isError: true,
        content: [
          TextContent(
            text:
                'Required parameter "enabled" was not provided or is not a '
                'boolean.',
          ),
        ],
      )..failureReason = CallToolFailureReason.argumentError;
    }

    return _callOnVmService(
      callback: (vmService) async {
        final vm = await vmService.getVM();
        final isolateId = vm.isolates!.first.id;
        try {
          final result = await vmService.callServiceExtension(
            '$_inspectorServiceExtensionPrefix.show',
            isolateId: isolateId,
            args: {'enabled': enabled.toString()},
          );

          if (result.json?['enabled'] == enabled ||
              result.json?['enabled'] == enabled.toString()) {
            return CallToolResult(
              content: [
                TextContent(
                  text:
                      'Widget selection mode '
                      '${enabled ? 'enabled' : 'disabled'}.',
                ),
              ],
            );
          }
          return CallToolResult(
            isError: true,
            content: [
              TextContent(
                text:
                    'Failed to set widget selection mode. Unexpected response: '
                    '${result.json}',
              ),
            ],
          );
        } catch (e) {
          return CallToolResult(
            isError: true,
            content: [
              TextContent(text: 'Failed to set widget selection mode: $e'),
            ],
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
    if (!_connectedAppServiceIsSupported) return _connectedAppsNotSupported;

    await updateActiveVmServices();
    if (activeVmServices.isEmpty) return _noActiveDebugSession;

    // TODO: support selecting a VM Service if more than one are available.
    final vmService = activeVmServices.values.first;
    return await callback(await vmService);
  }

  /// Retrieves the active location from the editor.
  Future<CallToolResult> _getActiveLocation(CallToolRequest request) async {
    if (_dtd == null) return _dtdNotConnected;

    final activeLocation = _activeLocation;
    if (activeLocation == null) {
      return CallToolResult(
        content: [
          TextContent(text: 'No active location reported by the editor yet.'),
        ],
      );
    }

    return CallToolResult(
      content: [TextContent(text: jsonEncode(_activeLocation))],
    );
  }

  @visibleForTesting
  static final connectTool = Tool(
    name: 'connect_dart_tooling_daemon',
    description:
        'Connects to the Dart Tooling Daemon. You should get the uri either '
        'from available tools or the user, do not just make up a random URI to '
        'pass. When asking the user for the uri, you should suggest the "Copy '
        'DTD Uri to clipboard" action. When reconnecting after losing a '
        'connection, always request a new uri first.',
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
        'Retrieves the most recent runtime errors that have occurred in the '
        'active Dart or Flutter application. Requires "${connectTool.name}" to '
        'be successfully called first.',
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

  @visibleForTesting
  static final setWidgetSelectionModeTool = Tool(
    name: 'set_widget_selection_mode',
    description:
        'Enables or disables widget selection mode in the active Flutter '
        'application. Requires "${connectTool.name}" to be successfully called '
        'first.',
    annotations: ToolAnnotations(
      title: 'Set Widget Selection Mode',
      readOnlyHint: true,
    ),
    inputSchema: Schema.object(
      properties: {
        'enabled': Schema.bool(title: 'Enable widget selection mode'),
      },
      required: const ['enabled'],
    ),
  );

  @visibleForTesting
  static final getActiveLocationTool = Tool(
    name: 'get_active_location',
    description:
        'Retrieves the current active location (e.g., cursor position) in the '
        'connected editor. Requires "${connectTool.name}" to be successfully '
        'called first.',
    annotations: ToolAnnotations(
      title: 'Get Active Editor Location',
      readOnlyHint: true,
    ),
    inputSchema: Schema.object(),
  );

  static final _connectedAppsNotSupported = CallToolResult(
    isError: true,
    content: [
      TextContent(
        text:
            'A Dart SDK of version 3.9.0-163.0.dev or greater is required to '
            'connect to Dart and Flutter applications.',
      ),
    ],
  )..failureReason = CallToolFailureReason.connectedAppServiceNotSupported;

  static final _dtdNotConnected = CallToolResult(
    isError: true,
    content: [
      TextContent(
        text:
            'The dart tooling daemon is not connected, you need to call '
            '"${connectTool.name}" first.',
      ),
    ],
  )..failureReason = CallToolFailureReason.dtdNotConnected;

  static final _dtdAlreadyConnected = CallToolResult(
    isError: true,
    content: [
      TextContent(
        text:
            'The dart tooling daemon is already connected, you cannot call '
            '"${connectTool.name}" again.',
      ),
    ],
  )..failureReason = CallToolFailureReason.dtdAlreadyConnected;

  static final _noActiveDebugSession = CallToolResult(
    content: [
      TextContent(text: 'No active debug session to take a screenshot'),
    ],
    isError: true,
  )..failureReason = CallToolFailureReason.noActiveDebugSession;

  static final runtimeErrorsScheme = 'runtime-errors';
}

/// Listens on a VM service for errors.
class _AppErrorsListener {
  /// All the errors recorded so far (may be cleared explicitly).
  final ErrorLog errorLog;

  /// A broadcast stream of all errors that come in after you start listening.
  Stream<String> get errorsStream => _errorsController.stream;

  /// Controller for the [errorsStream].
  final StreamController<String> _errorsController;

  /// The listener for Flutter.Error vm service extension events.
  final StreamSubscription<Event>? _extensionEventsListener;

  /// The stderr listener on the flutter process.
  final StreamSubscription<Event>? _stderrEventsListener;

  /// The vm service instance connected to the flutter app.
  final VmService _vmService;

  _AppErrorsListener._(
    this.errorLog,
    this._errorsController,
    this._extensionEventsListener,
    this._stderrEventsListener,
    this._vmService,
  ) {
    _vmService.onDone.then((_) => shutdown());
  }

  /// Maintain a cache of error listeners by [VmService] instance as an
  /// [Expando] so we don't have to worry about explicit cleanup.
  static final _errorListeners = Expando<Future<_AppErrorsListener>>();

  /// Returns the canonical [_AppErrorsListener] for the [vmService] instance,
  /// which may be an already existing instance.
  static Future<_AppErrorsListener> forVmService(
    VmService vmService,
    LoggingSupport logger,
  ) async {
    return _errorListeners[vmService] ??= () async {
      // Needs to be a broadcast stream because we use it to add errors to the
      // list but also expose it to clients so they can know when new errors
      // are added.
      final errorsController = StreamController<String>.broadcast();
      final errorLog = ErrorLog();
      errorsController.stream.listen(errorLog.add);
      // We need to listen to streams with history so that we can get errors
      // that occurred before this tool call.
      // TODO(https://github.com/dart-lang/ai/issues/57): this can result in
      // duplicate errors that we need to de-duplicate somehow.
      StreamSubscription<Event>? extensionEvents;
      StreamSubscription<Event>? stderrEvents;

      try {
        extensionEvents = vmService.onExtensionEventWithHistory.listen((
          Event e,
        ) {
          if (e.extensionKind == 'Flutter.Error') {
            // TODO(https://github.com/dart-lang/ai/issues/57): consider
            // pruning this content down to only what is useful for the LLM to
            // understand the error and its source.
            errorsController.add(e.json.toString());
          }
        });
        Event? lastError;
        stderrEvents = vmService.onStderrEventWithHistory.listen((Event e) {
          if (lastError case final last?
              when last.timestamp == e.timestamp && last.bytes == e.bytes) {
            // Looks like a duplicate event, on Dart 3.7 stable we get these.
            return;
          }
          lastError = e;
          final message = decodeBase64(e.bytes!);
          // TODO(https://github.com/dart-lang/ai/issues/57): consider
          // pruning this content down to only what is useful for the LLM to
          // understand the error and its source.
          errorsController.add(message);
        });

        await [
          vmService.streamListen(EventStreams.kExtension),
          vmService.streamListen(EventStreams.kStderr),
        ].wait;
      } catch (e) {
        logger.log(LoggingLevel.error, 'Error subscribing to app errors: $e');
      }
      return _AppErrorsListener._(
        errorLog,
        errorsController,
        extensionEvents,
        stderrEvents,
        vmService,
      );
    }();
  }

  Future<void> shutdown() async {
    errorLog.clear();
    await _errorsController.close();
    await _extensionEventsListener?.cancel();
    await _stderrEventsListener?.cancel();
    try {
      await _vmService.streamCancel(EventStreams.kExtension);
      await _vmService.streamCancel(EventStreams.kStderr);
    } on RPCError catch (_) {
      // The vm service might already be disposed in which causes these to fail.
    }
  }
}

/// Manages a log of errors with a maximum size in terms of total characters.
@visibleForTesting
class ErrorLog {
  Iterable<String> get errors => _errors;
  final List<String> _errors = [];
  int _characters = 0;

  /// The number of characters used by all errors in the log.
  @visibleForTesting
  int get characters => _characters;

  final int _maxSize;

  ErrorLog({
    // One token is ~4 characters. Allow up to 5k tokens by default, so 20k
    // characters.
    int maxSize = 20000,
  }) : _maxSize = maxSize;

  /// Adds a new [error] to the log.
  void add(String error) {
    if (error.length > _maxSize) {
      // If we get a single error over the max size, just trim it and clear
      // all other errors.
      final trimmed = error.substring(0, _maxSize);
      _errors.clear();
      _characters = trimmed.length;
      _errors.add(trimmed);
    } else {
      // Otherwise, we append the error and then remove as many errors from the
      // front as we need to in order to get under the max size.
      _characters += error.length;
      _errors.add(error);
      var removeCount = 0;
      while (_characters > _maxSize) {
        _characters -= _errors[removeCount].length;
        removeCount++;
      }
      _errors.removeRange(0, removeCount);
    }
  }

  /// Clears all errors.
  void clear() {
    _characters = 0;
    _errors.clear();
  }
}

extension on VmService {
  static final _ids = Expando<String>();
  static int _nextId = 0;
  String get id => _ids[this] ??= '${_nextId++}';
}
