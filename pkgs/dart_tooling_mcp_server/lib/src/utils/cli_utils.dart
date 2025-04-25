// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:process/process.dart';

/// Runs [command] in each of the project roots specified in the [request].
///
/// The [command] should be a list of strings that can be passed directly to
/// [ProcessManager.run].
///
/// The [commandDescription] is used in the output to describe the command
/// being run. For example, if the command is `['dart', 'fix', '--apply']`, the
/// command description might be `dart fix`.
///
/// [defaultPaths] may be specified if one or more path arguments are required
/// for the command (e.g. `dart format <default paths>`). The paths can be
/// absolute or relative paths that point to the directories on which the
/// command should be run. For example, the `dart format` command may pass a
/// default path of '.', which indicates that every Dart file in the working
/// directory should be formatted. The value of `defaultPaths` will only be used
/// if the [request]'s root configuration does not contain a set value for a
/// root's 'paths'.
Future<CallToolResult> runCommandInRoots(
  CallToolRequest request, {
  required List<String> command,
  required String commandDescription,
  required ProcessManager processManager,
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
          TextContent(text: 'Invalid root configuration: missing `root` key.'),
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

    final commandWithPaths = List<String>.from(command);
    final paths = (rootConfig['paths'] as List?)?.cast<String>();
    commandWithPaths.addAll(paths ?? defaultPaths);

    final result = await processManager.run(
      commandWithPaths,
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
                '$commandDescription failed in ${projectRoot.path}:\n'
                '$output\n\nErrors\n$errors',
          ),
        ],
        isError: true,
      );
    }
    if (output.isNotEmpty) {
      outputs.add(
        TextContent(
          text: '$commandDescription in ${projectRoot.path}:\n$output',
        ),
      );
    }
  }
  return CallToolResult(content: outputs);
}
