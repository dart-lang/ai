// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/server.dart';

import '../utils/cli_utils.dart';
import '../utils/constants.dart';
import '../utils/file_system.dart';
import '../utils/process_manager.dart';

/// Mix this in to any MCPServer to add support for running Dart or Flutter CLI
/// commands like `dart fix`, `dart format`, and `flutter test`.
///
/// The MCPServer must already have the [ToolsSupport] and [LoggingSupport]
/// mixins applied.
base mixin DashCliSupport on ToolsSupport, LoggingSupport, RootsTrackingSupport
    implements ProcessManagerSupport, FileSystemSupport {
  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    try {
      return super.initialize(request);
    } finally {
      // Can't call this until after `super.initialize`.
      if (supportsRoots) {
        registerTool(dartFixTool, _runDartFixTool);
        registerTool(dartFormatTool, _runDartFormatTool);
        registerTool(runTestsTool, _runTests);
      }
    }
  }

  /// Implementation of the [dartFixTool].
  Future<CallToolResult> _runDartFixTool(CallToolRequest request) async {
    return runCommandInRoots(
      request,
      commandForRoot: (_, _) => 'dart',
      arguments: ['fix', '--apply'],
      commandDescription: 'dart fix',
      processManager: processManager,
      knownRoots: await roots,
      fileSystem: fileSystem,
    );
  }

  /// Implementation of the [dartFormatTool].
  Future<CallToolResult> _runDartFormatTool(CallToolRequest request) async {
    return runCommandInRoots(
      request,
      commandForRoot: (_, _) => 'dart',
      arguments: ['format'],
      commandDescription: 'dart format',
      processManager: processManager,
      defaultPaths: ['.'],
      knownRoots: await roots,
      fileSystem: fileSystem,
    );
  }

  /// Implementation of the [runTestsTool].
  Future<CallToolResult> _runTests(CallToolRequest request) async {
    return runCommandInRoots(
      request,
      arguments: ['test'],
      commandDescription: 'dart|flutter test',
      processManager: processManager,
      knownRoots: await roots,
      fileSystem: fileSystem,
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

  static final runTestsTool = Tool(
    name: 'run_tests',
    description: 'Runs Dart or Flutter tests for the given project roots.',
    annotations: ToolAnnotations(title: 'Run tests', readOnlyHint: true),
    inputSchema: Schema.object(
      properties: {ParameterNames.roots: rootsSchema(supportsPaths: true)},
    ),
  );
}
