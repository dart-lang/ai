// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:collection';

import 'package:async/async.dart';

import 'package:dart_mcp/server.dart';
import 'package:meta/meta.dart';

import '../features_configuration.dart';
import '../utils/constants.dart';
import '../utils/names.dart';

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

  /// Always supported, either by the client or this mixin.
  @override
  bool get supportsRoots => true;

  @override
  bool get supportsRootsChanged => true;

  /// Combines the client stream and the fallback controller stream.
  @override
  Stream<RootsListChangedNotification?> get rootsListChanged {
    final clientStream = super.rootsListChanged;
    if (clientStream == null) {
      return _rootsListChangedFallbackController.stream;
    }
    return StreamGroup.merge([
      clientStream,
      _rootsListChangedFallbackController.stream,
    ]);
  }

  /// Broadcast controller for roots list changed events from usage of the
  /// roots tool.
  final _rootsListChangedFallbackController =
      StreamController<RootsListChangedNotification?>.broadcast();

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) async {
    try {
      return super.initialize(request);
    } finally {
      registerTool(rootsTool, _roots);
    }
  }

  @visibleForTesting
  static final List<Tool> allTools = [rootsTool];

  @override
  Future<ListRootsResult> listRoots([ListRootsRequest? request]) async {
    final clientRoots = <Root>[];
    if (super.supportsRoots) {
      try {
        final result = await super.listRoots(request);
        clientRoots.addAll(result.roots);
      } catch (e, s) {
        log(LoggingLevel.error, 'Failed to list roots from client: $e\n$s');
      }
    }

    final seenUris = <String>{};
    final allRoots = <Root>[];

    for (final root in clientRoots.followedBy(_customRoots)) {
      if (seenUris.add(root.uri)) {
        allRoots.add(root);
      }
    }

    return ListRootsResult(roots: allRoots);
  }

  /// Handles requests to the roots tool, delegating to the subcommand.
  Future<CallToolResult> _roots(CallToolRequest request) async {
    final command = request.arguments![ParameterNames.command] as String;
    switch (command) {
      case RootsCommands.add:
        return _addRoots(request);
      case RootsCommands.remove:
        return _removeRoots(request);
      default:
        return CallToolResult(
          isError: true,
          content: [TextContent(text: 'Unknown command: $command')],
        );
    }
  }

  Future<CallToolResult> _addRoots(CallToolRequest request) async {
    final uris = (request.arguments?[ParameterNames.uris] as List)
        .cast<String>();
    _customRoots.addAll(uris.map((u) => Root(uri: u)));
    _rootsListChangedFallbackController.add(RootsListChangedNotification());
    return success;
  }

  Future<CallToolResult> _removeRoots(CallToolRequest request) async {
    final uris = (request.arguments?[ParameterNames.uris] as List)
        .cast<String>();
    _customRoots.removeAll(uris.map((u) => Root(uri: u)));
    _rootsListChangedFallbackController.add(RootsListChangedNotification());
    return success;
  }

  @override
  Future<void> shutdown() async {
    await super.shutdown();
    await _rootsListChangedFallbackController.close();
  }

  @visibleForTesting
  static final rootsTool = Tool(
    name: ToolNames.roots.name,
    description: 'Manage project roots.',
    inputSchema: Schema.object(
      properties: {
        ParameterNames.command: EnumSchema.untitledSingleSelect(
          description: 'The command to execute.',
          values: [RootsCommands.add, RootsCommands.remove],
        ),
        ParameterNames.uris: Schema.list(
          description: 'The URIs to add or remove as roots.',
          items: Schema.string(),
        ),
      },
      required: [ParameterNames.command, ParameterNames.uris],
      additionalProperties: false,
    ),
  )..categories = [FeatureCategory.all];
}

extension RootsCommands on Never {
  static const add = 'add';
  static const remove = 'remove';
}
