// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/server.dart';
import 'package:path/path.dart' as p;

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
        registerTool(createProjectTool, _runCreateProjectTool);
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

  /// Implementation of the [createProjectTool].
  Future<CallToolResult> _runCreateProjectTool(CallToolRequest request) async {
    final args = request.arguments;

    final errors = createProjectTool.inputSchema.validate(args);
    final projectType = args?[ParameterNames.projectType] as String?;
    if (projectType != 'dart' && projectType != 'flutter') {
      errors.add(
        ValidationError(
          ValidationErrorType.itemInvalid,
          path: [ParameterNames.projectType],
          details: 'Only `dart` and `flutter` are allowed values.',
        ),
      );
    }
    final directory = args![ParameterNames.directory] as String;
    if (p.isAbsolute(directory)) {
      errors.add(
        ValidationError(
          ValidationErrorType.itemInvalid,
          path: [ParameterNames.directory],
          details: 'Directory must be a relative path.',
        ),
      );
    }

    if (errors.isNotEmpty) {
      return CallToolResult(
        content: [
          for (final error in errors) Content.text(text: error.toErrorString()),
        ],
        isError: true,
      );
    }

    final template = args[ParameterNames.template] as String?;

    final commandArgs = [
      'create',
      if (template != null && template.isNotEmpty) ...['--template', template],
      directory,
    ];

    return runCommandInRoot(
      request,
      arguments: commandArgs,
      commandForRoot: (_, _) => projectType!,
      commandDescription: '$projectType create',
      fileSystem: fileSystem,
      processManager: processManager,
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

  static final runTestsTool = Tool(
    name: 'run_tests',
    description: 'Runs Dart or Flutter tests for the given project roots.',
    annotations: ToolAnnotations(title: 'Run tests', readOnlyHint: true),
    inputSchema: Schema.object(
      properties: {ParameterNames.roots: rootsSchema(supportsPaths: true)},
    ),
  );

  static final createProjectTool = Tool(
    name: 'create_project',
    description: 'Creates a new Dart or Flutter project.',
    annotations: ToolAnnotations(
      title: 'Create project',
      destructiveHint: true,
    ),
    inputSchema: Schema.object(
      properties: {
        ParameterNames.root: rootSchema,
        ParameterNames.directory: Schema.string(
          description:
              'The subdirectory in which to create the project, must '
              'be a relative path.',
        ),
        ParameterNames.projectType: Schema.string(
          description: "The type of project: 'dart' or 'flutter'.",
        ),
        ParameterNames.template: Schema.string(
          description:
              'The project template to use (e.g., "console-full", "app").',
        ),
      },
      required: [ParameterNames.directory, ParameterNames.projectType],
    ),
  );
}
