// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/server.dart';

import '../utils/cli_utils.dart';
import '../utils/process_manager.dart';

// TODO: migrate the analyze files tool to use this mixin and run the
// `dart analyze` command instead of the analyzer package.

/// Mix this in to any MCPServer to add support for running Dart CLI commands
/// like `dart fix` and `dart format`.
///
/// The MCPServer must already have the [ToolsSupport] and [LoggingSupport]
/// mixins applied.
base mixin DartCliSupport on ToolsSupport, LoggingSupport
    implements ProcessManagerSupport {
  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    if (request.capabilities.roots == null) {
      throw StateError(
        'This server requires the "roots" capability to be implemented.',
      );
    }
    registerTool(dartFixTool, _runDartFixTool);
    registerTool(dartFormatTool, _runDartFormatTool);
    return super.initialize(request);
  }

  /// Implementation of the [dartFixTool].
  Future<CallToolResult> _runDartFixTool(CallToolRequest request) async {
    return runCommandInRoots(
      request,
      command: ['dart', 'fix', '--apply'],
      commandDescription: 'dart fix',
      processManager: processManager,
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
    );
  }

  static final dartFixTool = Tool(
    name: 'dart_fix',
    description: 'Runs `dart fix --apply` for the given project roots.',
    annotations: ToolAnnotations(title: 'Dart fix', destructiveHint: true),
    inputSchema: Schema.object(
      properties: {
        'roots': Schema.list(
          title: 'All projects roots to run dart fix in.',
          description:
              'These must match a root returned by a call to "listRoots".',
          items: Schema.object(
            properties: {
              'root': Schema.string(
                title: 'The URI of the project root to run `dart fix` in.',
              ),
            },
            required: ['root'],
          ),
        ),
      },
      required: ['roots'],
    ),
  );

  static final dartFormatTool = Tool(
    name: 'dart_format',
    description: 'Runs `dart format .` for the given project roots.',
    annotations: ToolAnnotations(title: 'Dart format', destructiveHint: true),
    inputSchema: Schema.object(
      properties: {
        'roots': Schema.list(
          title: 'All projects roots to run dart format in.',
          description:
              'These must match a root returned by a call to "listRoots".',
          items: Schema.object(
            properties: {
              'root': Schema.string(
                title: 'The URI of the project root to run `dart format` in.',
              ),
              'paths': Schema.list(
                title:
                    'Relative or absolute paths to analyze under the '
                    '"root". Paths must correspond to files and not '
                    'directories.',
                items: Schema.string(),
              ),
            },
            required: ['root'],
          ),
        ),
      },
      required: ['roots'],
    ),
  );
}
