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

  @override
  bool get supportsRoots => true;

  @override
  bool get supportsRootsChanged =>
      // If the client supports roots, then we only support root change events
      // if they do. If we are implementing the support, we always support it.
      super.supportsRoots ? super.supportsRootsChanged : true;

  @override
  Stream<RootsListChangedNotification>? get rootsListChanged =>
      // If the client supports roots, just use their stream (or lack thereof).
      // If they don't, use our own stream.
      super.supportsRoots
          ? super.rootsListChanged
          : _rootsListChangedFallbackController?.stream;
  StreamController<RootsListChangedNotification>?
  _rootsListChangedFallbackController;

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) async {
    try {
      return super.initialize(request);
    } finally {
      // Can't call `super.supportsRoots` until after `super.initialize`.
      if (!super.supportsRoots) {
        registerTool(removeRootsTool, _removeRoots);
        registerTool(addRootsTool, _addRoots);
        _rootsListChangedFallbackController =
            StreamController<RootsListChangedNotification>.broadcast();
      }
    }
  }

  /// Delegates to the inherited implementation if [supportsRoots] is true,
  /// otherwise returns our own custom roots.
  @override
  Future<ListRootsResult> listRoots(ListRootsRequest request) async =>
      super.supportsRoots
          ? super.listRoots(request)
          : ListRootsResult(roots: _customRoots.toList());

  /// Adds the roots in [request] the custom roots and calls [updateRoots].
  ///
  /// Should only be called if [supportsRoots] is false.
  Future<CallToolResult> _addRoots(CallToolRequest request) async {
    if (super.supportsRoots) {
      throw StateError(
        'This tool should not be invoked if the client supports roots',
      );
    }

    final roots =
        (request.arguments![ParameterNames.roots] as List).cast<Root>();
    for (final root in roots) {
      _customRoots.add(root);
    }
    _rootsListChangedFallbackController?.add(RootsListChangedNotification());
    return CallToolResult(content: [Content.text(text: 'Success')]);
  }

  /// Removes the roots in [request] from the custom roots and calls
  /// [updateRoots].
  ///
  /// Should only be called if [supportsRoots] is false.
  Future<CallToolResult> _removeRoots(CallToolRequest request) async {
    if (super.supportsRoots) {
      throw StateError(
        'This tool should not be invoked if the client supports roots',
      );
    }

    final roots = (request.arguments![ParameterNames.uris] as List)
        .cast<String>()
        .map((uri) => Root(uri: uri));
    _customRoots.removeAll(roots);
    _rootsListChangedFallbackController?.add(RootsListChangedNotification());

    return CallToolResult(content: [Content.text(text: 'Success')]);
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
