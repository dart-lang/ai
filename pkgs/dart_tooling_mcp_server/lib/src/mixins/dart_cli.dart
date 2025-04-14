// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:dart_mcp/server.dart';

// TODO: migrate the analyze files tool to use this mixin and run the
// `dart analyze` command instead of the analyzer package.

/// Mix this in to any MCPServer to add support for running Dart CLI commands
/// like `dart fix` and `dart format`.
///
/// The MCPServer must already have the [ToolsSupport] and [LoggingSupport]
/// mixins applied.
base mixin DartCliSupport on ToolsSupport, LoggingSupport {
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
    return _runDartCommandInRoots(request, 'dart fix', ['fix', '--apply']);
  }

  /// Implementation of the [dartFormatTool].
  Future<CallToolResult> _runDartFormatTool(CallToolRequest request) async {
    return _runDartCommandInRoots(
      request,
      'dart format',
      ['format'],
      defaultPaths: ['.'],
    );
  }

  /// Helper to run a dart command in multiple project roots.
  ///
  /// [defaultPaths] may be specified if one or more path arguments are required
  /// for the dart command (e.g. `dart format <default paths>`).
  Future<CallToolResult> _runDartCommandInRoots(
    CallToolRequest request,
    String commandName,
    List<String> commandArgs, {
    List<String> defaultPaths = const <String>[],
  }) async {
    final rootConfigs =
        (request.arguments?['roots'] as List?)?.cast<Map<String, Object?>>();
    if (rootConfigs == null) {
      return CallToolResult(
        content: [TextContent(text: 'Missing required argument `roots`.')],
        isError: true,
      );
    }

    final outputs = <TextContent>[];
    for (var rootConfig in rootConfigs) {
      final rootUriString = rootConfig['root'] as String?;
      if (rootUriString == null) {
        // This shouldn't happen based on the schema, but handle defensively.
        return CallToolResult(
          content: [
            TextContent(
              text: 'Invalid root configuration: missing `root` key.',
            ),
          ],
          isError: true,
        );
      }

      final rootUri = Uri.parse(rootUriString);
      if (rootUri.scheme != 'file') {
        return CallToolResult(
          content: [
            TextContent(
              text:
                  'Only file scheme uris are allowed for roots, but got '
                  '$rootUri',
            ),
          ],
          isError: true,
        );
      }
      final projectRoot = Directory(rootUri.toFilePath());

      final paths = (rootConfig['paths'] as List?)?.cast<String>();
      if (paths != null) {
        commandArgs.addAll(paths);
      } else {
        commandArgs.addAll(defaultPaths);
      }

      final result = await Process.run(
        'dart',
        commandArgs,
        workingDirectory: projectRoot.path,
        runInShell: true,
      );

      final output = (result.stdout as String).trim();
      final errors = (result.stderr as String).trim();
      if (result.exitCode != 0) {
        return CallToolResult(
          content: [
            TextContent(
              text:
                  '$commandName failed in ${projectRoot.path}:\n$output\n\n'
                  'Errors\n$errors',
            ),
          ],
          isError: true,
        );
      }
      if (output.isNotEmpty) {
        outputs.add(
          TextContent(text: '$commandName in ${projectRoot.path}:\n$output'),
        );
      }
    }
    return CallToolResult(content: outputs);
  }

  static final dartFixTool = Tool(
    name: 'dart_fix',
    description: 'Runs `dart fix --apply` for the given project roots.',
    inputSchema: ObjectSchema(
      properties: {
        'roots': ListSchema(
          title: 'All projects roots to run dart fix in.',
          description:
              'These must match a root returned by a call to "listRoots".',
          items: ObjectSchema(
            properties: {
              'root': StringSchema(
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
    inputSchema: ObjectSchema(
      properties: {
        'roots': ListSchema(
          title: 'All projects roots to run dart format in.',
          description:
              'These must match a root returned by a call to "listRoots".',
          items: ObjectSchema(
            properties: {
              'root': StringSchema(
                title: 'The URI of the project root to run `dart format` in.',
              ),
              'paths': ListSchema(
                title:
                    'Relative or absolute paths to analyze under the '
                    '"root". Paths must correspond to files and not '
                    'directories.',
                items: StringSchema(),
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
