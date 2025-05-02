// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/server.dart';

import '../utils/cli_utils.dart';
import '../utils/constants.dart';
import '../utils/process_manager.dart';

// TODO: migrate the analyze files tool to use this mixin and run the
// `dart analyze` command instead of the analyzer package.

/// Mix this in to any MCPServer to add support for running Dart CLI commands
/// like `dart fix` and `dart format`.
///
/// The MCPServer must already have the [ToolsSupport] and [LoggingSupport]
/// mixins applied.
base mixin DartCliSupport on ToolsSupport, LoggingSupport, RootsTrackingSupport
    implements ProcessManagerSupport {
  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    try {
      return super.initialize(request);
    } finally {
      // Can't call this until after `super.initialize`.
      if (supportsRoots) {
        registerTool(dartFixTool, _runDartFixTool);
        registerTool(dartFormatTool, _runDartFormatTool);
      }
    }
  }

  /// Implementation of the [dartFixTool].
  Future<CallToolResult> _runDartFixTool(CallToolRequest request) async {
    return runCommandInRoots(
      request,
      command: ['dart', 'fix', '--apply'],
      commandDescription: 'dart fix',
      processManager: processManager,
      knownRoots: await roots,
    );
  }

  /// Implementation of the [dartFormatTool].
  Future<CallToolResult> _runDartFormatTool(CallToolRequest request) async {
    return runCommandInRoots(
      request,
      command: ['dart', 'format'],
      commandDescription: 'dart format',
      processManager: processManager,
      defaultPaths: ['.'],
      knownRoots: await roots,
    );
  }

  static final dartFixTool = Tool(
    name: 'dart_fix',
    description: 'Runs `dart fix --apply` for the given project roots.',
    annotations: ToolAnnotations(title: 'Dart fix', destructiveHint: true),
    inputSchema: Schema.object(
      properties: {ParameterNames.roots: rootsSchema()},
    ),
  );

  static final dartFormatTool = Tool(
    name: 'dart_format',
    description: 'Runs `dart format .` for the given project roots.',
    annotations: ToolAnnotations(title: 'Dart format', destructiveHint: true),
    inputSchema: Schema.object(
      properties: {ParameterNames.roots: rootsSchema(supportsPaths: true)},
    ),
  );
}
