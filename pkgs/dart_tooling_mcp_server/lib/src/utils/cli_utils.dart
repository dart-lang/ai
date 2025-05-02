// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:path/path.dart' as p;
import 'package:process/process.dart';

import 'constants.dart';

/// Runs [command] in each of the project roots specified in the [request].
///
/// The [command] should be a list of strings that can be passed directly to
/// [ProcessManager.run].
///
/// The [commandDescription] is used in the output to describe the command
/// being run. For example, if the command is `['dart', 'fix', '--apply']`, the
/// command description might be `dart fix`.
///
/// The [knownRoots] are used by default if no roots are provided as an
/// argument on the [request]. Otherwise, all roots provided in the request
/// arguments must still be encapsulated by the [knownRoots].
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
  required List<Root> knownRoots,
  List<String> defaultPaths = const <String>[],
}) async {
  var rootConfigs =
      (request.arguments?[ParameterNames.roots] as List?)
          ?.cast<Map<String, Object?>>();

  // Default to use the known roots if none were specified.
  if (rootConfigs == null || rootConfigs.isEmpty) {
    rootConfigs = [
      for (final root in knownRoots) {ParameterNames.root: root.uri},
    ];
  }

  final outputs = <TextContent>[];
  for (var rootConfig in rootConfigs) {
    final rootUriString = rootConfig[ParameterNames.root] as String?;
    if (rootUriString == null) {
      // This shouldn't happen based on the schema, but handle defensively.
      return CallToolResult(
        content: [
          TextContent(text: 'Invalid root configuration: missing `root` key.'),
        ],
        isError: true,
      );
    }

    if (!_isAllowedRoot(rootUriString, knownRoots)) {
      return CallToolResult(
        content: [
          TextContent(
            text:
                'Invalid root $rootUriString, must be under one of the '
                'registered project roots:\n\n${knownRoots.join('\n')}',
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

    final commandWithPaths = List.of(command);
    final paths =
        (rootConfig[ParameterNames.paths] as List?)?.cast<String>() ??
        defaultPaths;
    final invalidPaths = paths.where((path) {
      final resolvedPath = rootUri.resolve(path).toString();
      return rootUriString != resolvedPath &&
          !p.isWithin(rootUriString, resolvedPath);
    });
    if (invalidPaths.isNotEmpty) {
      return CallToolResult(
        content: [
          TextContent(
            text:
                'Paths are not allowed to escape their project root:\n'
                '${invalidPaths.join('\n')}',
          ),
        ],
        isError: true,
      );
    }
    commandWithPaths.addAll(paths);

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

/// Returns whether or not [rootUri] is an allowed root, either exactly matching
/// or under on of the [knownRoots].
bool _isAllowedRoot(String rootUri, List<Root> knownRoots) =>
    knownRoots.any((knownRoot) {
      final knownRootUri = Uri.parse(knownRoot.uri);
      final resolvedRoot = knownRootUri.resolve(rootUri).toString();
      return knownRoot.uri == resolvedRoot ||
          p.isWithin(knownRoot.uri, resolvedRoot);
    });

/// The schema for the `roots` parameter for any tool that accepts it.
ListSchema rootsSchema({bool supportsPaths = false}) => Schema.list(
  title: 'All projects roots to run this tool in.',
  items: Schema.object(
    properties: {
      ParameterNames.root: Schema.string(
        title: 'The URI of the project root to run this tool in.',
        description:
            'This must be equal to or a subdirectory of one of the roots '
            'returned by a call to "listRoots".',
      ),
      if (supportsPaths)
        ParameterNames.paths: Schema.list(
          title:
              'Paths to run this tool on. Must resolve to a path that is '
              'within the "root".',
        ),
    },
    required: [ParameterNames.root],
  ),
);
