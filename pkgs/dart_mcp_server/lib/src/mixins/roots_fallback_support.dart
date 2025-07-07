// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:collection';

import 'package:dart_mcp/server.dart';
import 'package:meta/meta.dart';

import '../utils/constants.dart';

/// Adds a fallback mode for roots when they aren't supported.
///
/// Overrides [listRoots] to return the manually added roots through
/// an MCP tool command.
///
/// Overrides [rootsListChanged] to return a custom stream of events based
/// on the tool calls.
base mixin RootsFallbackSupport on ToolsSupport, RootsTrackingSupport {
  /// Set of custom roots
  final Set<Root> _customRoots = HashSet<Root>(
    equals: (a, b) => a.uri == b.uri,
    hashCode: (root) => root.uri.hashCode,
  );

  /// Whether or not to force the fallback mode for roots, regardless of the
  /// client's reported support.
  ///
  /// Override this to enable it.
  bool get forceRootsFallback => false;

  /// Whether fallback mode is enabled.
  ///
  /// Unsafe to call until after the server is initialized.
  bool get _fallbackEnabled => forceRootsFallback || !super.supportsRoots;

  /// Always supported, either by the client or this mixin.
  @override
  bool get supportsRoots => true;

  @override
  bool get supportsRootsChanged =>
      // If the client supports roots, then we only support root change events
      // if they do. If we are implementing the support, we always support it.
      _fallbackEnabled ? true : super.supportsRootsChanged;

  @override
  Stream<RootsListChangedNotification>? get rootsListChanged =>
      // If the client supports roots, just use their stream (or lack thereof).
      // If they don't, use our own stream.
      _fallbackEnabled
      ? _rootsListChangedFallbackController?.stream
      : super.rootsListChanged;

  StreamController<RootsListChangedNotification>?
  _rootsListChangedFallbackController;

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) async {
    try {
      return super.initialize(request);
    } finally {
      // Can't call `super.supportsRoots` until after `super.initialize`.
      if (_fallbackEnabled) {
        registerTool(removeRootsTool, _removeRoots);
        registerTool(addRootsTool, _addRoots);
        _rootsListChangedFallbackController =
            StreamController<RootsListChangedNotification>.broadcast();
      }
    }
  }

  /// Delegates to the inherited implementation if fallback mode is not enabled,
  /// otherwise returns our own custom roots.
  @override
  Future<ListRootsResult> listRoots(ListRootsRequest request) async =>
      _fallbackEnabled
      ? ListRootsResult(roots: _customRoots.toList())
      : super.listRoots(request);

  /// Adds the roots in [request] the custom roots and calls [updateRoots].
  ///
  /// Should only be called if [_fallbackEnabled] is `true`.
  Future<CallToolResult> _addRoots(CallToolRequest request) async {
    if (!_fallbackEnabled) {
      throw StateError(
        'This tool should not be invoked if the client supports roots',
      );
    }

    (request.arguments![ParameterNames.roots] as List).cast<Root>().forEach(
      _customRoots.add,
    );
    _rootsListChangedFallbackController?.add(RootsListChangedNotification());
    return success;
  }

  /// Removes the roots in [request] from the custom roots and calls
  /// [updateRoots].
  ///
  /// Should only be called if [_fallbackEnabled] is true.
  Future<CallToolResult> _removeRoots(CallToolRequest request) async {
    if (!_fallbackEnabled) {
      throw StateError(
        'This tool should not be invoked if the client supports roots',
      );
    }

    final roots = (request.arguments![ParameterNames.uris] as List)
        .cast<String>()
        .map((uri) => Root(uri: uri));
    _customRoots.removeAll(roots);
    _rootsListChangedFallbackController?.add(RootsListChangedNotification());

    return success;
  }

  @override
  Future<void> shutdown() async {
    await super.shutdown();
    await _rootsListChangedFallbackController?.close();
  }

  @visibleForTesting
  static final addRootsTool = Tool(
    name: 'add_roots',
    description:
        'Adds one or more project roots. Tools are only allowed to run under '
        'these roots, so you must call this function before passing any roots '
        'to any other tools.',
    annotations: ToolAnnotations(title: 'Add roots', readOnlyHint: false),
    inputSchema: Schema.object(
      properties: {
        ParameterNames.roots: Schema.list(
          description: 'All the project roots to add to this server.',
          items: Schema.object(
            properties: {
              ParameterNames.uri: Schema.string(
                description: 'The URI of the root.',
              ),
              ParameterNames.name: Schema.string(
                description: 'An optional name of the root.',
              ),
            },
            required: [ParameterNames.uri],
          ),
        ),
      },
    ),
  );

  @visibleForTesting
  static final removeRootsTool = Tool(
    name: 'remove_roots',
    description:
        'Removes one or more project roots previously added via '
        'the add_roots tool.',
    annotations: ToolAnnotations(title: 'Remove roots', readOnlyHint: false),
    inputSchema: Schema.object(
      properties: {
        ParameterNames.uris: Schema.list(
          description: 'All the project roots to remove from this server.',
          items: Schema.string(description: 'The URIs of the roots to remove.'),
        ),
      },
    ),
  );
}
