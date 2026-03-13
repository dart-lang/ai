// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:dart_mcp/server.dart';
import 'package:file/file.dart';
import 'package:meta/meta.dart';

import '../features_configuration.dart';
import '../utils/cli_utils.dart';
import '../utils/file_system.dart';
import '../utils/names.dart';

/// Adds tools for reading, writing, deleting, and listing files within the
/// workspace roots.
///
/// All operations are constrained to the known [roots] — paths outside any
/// configured root are rejected.
base mixin FileAccessSupport
    on ToolsSupport, RootsTrackingSupport
    implements FileSystemSupport {
  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    registerTool(readFileTool, _readFile);
    registerTool(writeFileTool, _writeFile);
    registerTool(deleteFileTool, _deleteFile);
    registerTool(listFilesTool, _listFiles);
    return super.initialize(request);
  }

  @visibleForTesting
  static final List<Tool> allTools = [
    readFileTool,
    writeFileTool,
    deleteFileTool,
    listFilesTool,
  ];

  /// Resolves [path] against the known roots and returns the resolved [Uri],
  /// or an error [CallToolResult] if the path is not allowed.
  ///
  /// A relative [path] is only permitted when exactly one root is configured,
  /// since there would otherwise be ambiguity about which root to resolve
  /// against.
  Future<({CallToolResult? error, Uri? resolvedUri})> _resolveAllowedPath(
    String path,
  ) async {
    final knownRoots = await roots;

    // Reject relative paths when multiple roots are configured.
    final parsedUri = Uri.tryParse(path);
    final isRelative =
        (parsedUri == null || !parsedUri.hasScheme) &&
        !fileSystem.path.isAbsolute(path);
    if (isRelative && knownRoots.length > 1) {
      return (
        error: CallToolResult(
          content: [
            TextContent(
              text:
                  'Path must be absolute when multiple roots are configured.',
            ),
          ],
          isError: true,
        ),
        resolvedUri: null,
      );
    }

    for (final root in knownRoots) {
      if (isUnderRoot(root, path, fileSystem)) {
        final rootUri = fileSystem.directory(Uri.parse(root.uri)).uri;
        final resolvedUri = rootUri.resolve(path);
        return (error: null, resolvedUri: resolvedUri);
      }
    }

    return (
      error: CallToolResult(
        content: [
          TextContent(
            text: 'Path $path is not under any of the known roots.',
          ),
        ],
        isError: true,
      ),
      resolvedUri: null,
    );
  }

  Future<CallToolResult> _readFile(CallToolRequest request) async {
    final path = request.arguments![ParameterNames.path] as String;
    final (:error, :resolvedUri) = await _resolveAllowedPath(path);
    if (error != null) return error;

    final file = fileSystem.file(resolvedUri);
    if (!await file.exists()) {
      return CallToolResult(
        content: [TextContent(text: 'File does not exist: $path')],
        isError: true,
      );
    }
    return CallToolResult(
      content: [TextContent(text: await file.readAsString())],
    );
  }

  Future<CallToolResult> _writeFile(CallToolRequest request) async {
    final path = request.arguments![ParameterNames.path] as String;
    final contents = request.arguments![ParameterNames.contents] as String;
    final (:error, :resolvedUri) = await _resolveAllowedPath(path);
    if (error != null) return error;

    final file = fileSystem.file(resolvedUri);
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    await file.writeAsString(contents);
    return CallToolResult(content: [TextContent(text: 'Success')]);
  }

  Future<CallToolResult> _deleteFile(CallToolRequest request) async {
    final path = request.arguments![ParameterNames.path] as String;
    final (:error, :resolvedUri) = await _resolveAllowedPath(path);
    if (error != null) return error;

    final file = fileSystem.file(resolvedUri);
    if (!await file.exists()) {
      return CallToolResult(
        content: [TextContent(text: 'File does not exist: $path')],
        isError: true,
      );
    }
    await file.delete();
    return CallToolResult(content: [TextContent(text: 'Success')]);
  }

  Future<CallToolResult> _listFiles(CallToolRequest request) async {
    final path = request.arguments![ParameterNames.path] as String;
    final (:error, :resolvedUri) = await _resolveAllowedPath(path);
    if (error != null) return error;

    final directory = fileSystem.directory(resolvedUri);
    if (!await directory.exists()) {
      return CallToolResult(
        content: [TextContent(text: 'Directory does not exist: $path')],
        isError: true,
      );
    }
    final entities = await directory.list().toList();
    return CallToolResult(
      content: [
        TextContent(
          text: jsonEncode([
            for (final entity in entities)
              {
                'uri': entity.uri.toString(),
                'kind': entity is Directory ? 'directory' : 'file',
              },
          ]),
        ),
      ],
    );
  }

  static final readFileTool = Tool(
    name: ToolNames.readFile.name,
    description:
        'Reads the contents of a file. '
        'Only files under the known workspace roots are accessible.',
    inputSchema: Schema.object(
      properties: {
        ParameterNames.path: Schema.string(
          description:
              'The path to the file to read. Can be a relative path '
              '(only when a single root is configured) or an absolute '
              'file URI (e.g. file:///absolute/path/to/file.dart).',
        ),
      },
      required: [ParameterNames.path],
    ),
    annotations: ToolAnnotations(readOnlyHint: true),
  )..categories = [FeatureCategory.all];

  static final writeFileTool = Tool(
    name: ToolNames.writeFile.name,
    description:
        'Writes content to a file, creating the file and any missing parent '
        'directories if they do not exist. '
        'Only files under the known workspace roots are accessible.',
    inputSchema: Schema.object(
      properties: {
        ParameterNames.path: Schema.string(
          description:
              'The path to the file to write. Can be a relative path '
              '(only when a single root is configured) or an absolute '
              'file URI (e.g. file:///absolute/path/to/file.dart).',
        ),
        ParameterNames.contents: Schema.string(
          description: 'The string contents to write to the file.',
        ),
      },
      required: [ParameterNames.path, ParameterNames.contents],
    ),
    annotations: ToolAnnotations(destructiveHint: true),
  )..categories = [FeatureCategory.all];

  static final deleteFileTool = Tool(
    name: ToolNames.deleteFile.name,
    description:
        'Deletes a file. '
        'Only files under the known workspace roots are accessible.',
    inputSchema: Schema.object(
      properties: {
        ParameterNames.path: Schema.string(
          description:
              'The path to the file to delete. Can be a relative path '
              '(only when a single root is configured) or an absolute '
              'file URI (e.g. file:///absolute/path/to/file.dart).',
        ),
      },
      required: [ParameterNames.path],
    ),
    annotations: ToolAnnotations(destructiveHint: true),
  )..categories = [FeatureCategory.all];

  static final listFilesTool = Tool(
    name: ToolNames.listFiles.name,
    description:
        'Lists the immediate children of a directory. '
        'Only directories under the known workspace roots are accessible.',
    inputSchema: Schema.object(
      properties: {
        ParameterNames.path: Schema.string(
          description:
              'The path to the directory to list. Can be a relative path '
              '(only when a single root is configured) or an absolute '
              'file URI (e.g. file:///absolute/path/to/dir/).',
        ),
      },
      required: [ParameterNames.path],
    ),
    annotations: ToolAnnotations(readOnlyHint: true),
  )..categories = [FeatureCategory.all];
}
