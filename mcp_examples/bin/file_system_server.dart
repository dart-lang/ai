// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:async/async.dart';
import 'package:dart_mcp/server.dart';
import 'package:path/path.dart' as p;
import 'package:stream_channel/stream_channel.dart';

void main() {
  SimpleFileSystemServer.fromStreamChannel(
    StreamChannel.withCloseGuarantee(io.stdin, io.stdout)
        .transform(StreamChannelTransformer.fromCodec(utf8))
        .transformStream(const LineSplitter())
        .transformSink(
          StreamSinkTransformer.fromHandlers(
            handleData: (data, sink) {
              sink.add('$data\n');
            },
          ),
        ),
  );
}

/// An basic file server implementation.
///
/// Only allows reading/writing to the tracked [roots], and only by utf8 string.
final class SimpleFileSystemServer extends MCPServer
    with LoggingSupport, RootsTrackingSupport, ToolsSupport {
  SimpleFileSystemServer.fromStreamChannel(super.channel)
    : super.fromStreamChannel(
        implementation: Implementation(name: 'file system', version: '0.0.1'),
      );

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    registerTool(readFileTool, _readFile);
    registerTool(writeFileTool, _writeFile);
    registerTool(deleteFileTool, _deleteFile);
    registerTool(listFilesTool, _listFiles);
    return super.initialize(request);
  }

  /// Checks if [path] is under any of the known [roots].
  ///
  /// If the path is valid, then the returned record will have a `resolvedUri`
  /// filled in, which should be used to read the file.
  ///
  /// Otherwise, the `error` will contain an appropriate error response.
  Future<({CallToolResult? error, String? resolvedUri})> _checkAllowedPath(
    String path,
  ) async {
    final roots = await this.roots;
    if (p.isRelative(path) && roots.length > 1) {
      return (
        error: CallToolResult(
          content: [
            TextContent(
              text: 'Path must be absolute when multiple roots are configured.',
            ),
          ],
          isError: true,
        ),
        resolvedUri: null,
      );
    }
    for (var root in roots) {
      final resolvedUri = Uri.parse(root.uri).resolve(path).toString();
      if (root.uri == resolvedUri || p.isWithin(root.uri, resolvedUri)) {
        return (error: null, resolvedUri: resolvedUri);
      }
    }
    return (
      error: CallToolResult(
        content: [
          TextContent(
            text: 'Path not allowed $path, must be under a known root.',
          ),
        ],
        isError: true,
      ),
      resolvedUri: null,
    );
  }

  Future<CallToolResult> _writeFile(CallToolRequest request) async {
    final (error: error, resolvedUri: resolvedUri) = await _checkAllowedPath(
      request.arguments!['path'] as String,
    );
    if (error != null) return error;

    final contents = request.arguments!['contents'] as String;
    final file = io.File.fromUri(Uri.parse(resolvedUri!));
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    await file.writeAsString(contents);
    return CallToolResult(content: [TextContent(text: 'Success')]);
  }

  Future<CallToolResult> _readFile(CallToolRequest request) async {
    final (error: error, resolvedUri: resolvedUri) = await _checkAllowedPath(
      request.arguments!['path'] as String,
    );
    if (error != null) return error;

    final file = io.File.fromUri(Uri.parse(resolvedUri!));
    if (!await file.exists()) {
      return CallToolResult(
        content: [TextContent(text: 'File does not exist')],
        isError: true,
      );
    }
    return CallToolResult(
      content: [TextContent(text: await file.readAsString())],
    );
  }

  Future<CallToolResult> _deleteFile(CallToolRequest request) async {
    final (error: error, resolvedUri: resolvedUri) = await _checkAllowedPath(
      request.arguments!['path'] as String,
    );
    if (error != null) return error;

    final file = io.File.fromUri(Uri.parse(resolvedUri!));
    if (!await file.exists()) {
      return CallToolResult(
        content: [TextContent(text: 'File does not exist')],
        isError: true,
      );
    }
    await file.delete();
    return CallToolResult(content: [TextContent(text: 'Success')]);
  }

  Future<CallToolResult> _listFiles(CallToolRequest request) async {
    final (error: error, resolvedUri: resolvedUri) = await _checkAllowedPath(
      request.arguments!['path'] as String,
    );
    if (error != null) return error;

    final directory = io.Directory.fromUri(Uri.parse(resolvedUri!));
    if (!await directory.exists()) {
      return CallToolResult(
        content: [TextContent(text: 'Directory does not exist')],
      );
    }
    final entities = await directory.list().toList();
    return CallToolResult(
      content: [
        TextContent(
          text: jsonEncode([
            for (var entity in entities)
              {
                'uri': entity.uri.toString(),
                'kind': entity is io.Directory ? 'directory' : 'file',
              },
          ]),
        ),
      ],
    );
  }

  final writeFileTool = Tool(
    name: 'writeFile',
    description: 'Writes a file to the file system.',
    inputSchema: Schema.object(
      properties: {
        'path': Schema.string(description: 'The path to the file to write.'),
        'contents': Schema.string(
          description: 'The string contents to write to the file.',
        ),
      },
    ),
    annotations: ToolAnnotations(destructiveHint: true),
  );

  final readFileTool = Tool(
    name: 'readFile',
    description: 'Reads a file from the file system.',
    inputSchema: Schema.object(
      properties: {
        'path': Schema.string(description: 'The path to the file to read.'),
      },
    ),
    annotations: ToolAnnotations(readOnlyHint: true),
  );

  final deleteFileTool = Tool(
    name: 'deleteFile',
    description: 'Deletes a file from the file system.',
    inputSchema: Schema.object(
      properties: {
        'path': Schema.string(description: 'The path to the file to delete.'),
      },
    ),
    annotations: ToolAnnotations(destructiveHint: true),
  );

  final listFilesTool = Tool(
    name: 'listFiles',
    description: 'Lists files in a directory.',
    inputSchema: Schema.object(
      properties: {
        'path': Schema.string(
          description: 'The path to the directory to list.',
        ),
      },
    ),
    annotations: ToolAnnotations(readOnlyHint: true),
  );
}
