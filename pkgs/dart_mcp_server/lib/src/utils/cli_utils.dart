// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/server.dart';
import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:process/process.dart';
import 'package:yaml/yaml.dart';

import 'constants.dart';
import 'sdk.dart';

/// The supported kinds of projects.
enum ProjectKind {
  /// A Flutter project
  flutter,

  /// A Dart project
  dart,

  /// An unknown project, this usually means there was no pubspec.yaml.
  unknown,
}

/// Infers the [ProjectKind] of a given [Root].
///
/// Currently, this is done by checking for the existence of a `pubspec.yaml`
/// file and whether it contains a Flutter SDK dependency.
Future<ProjectKind> inferProjectKind(Root root, FileSystem fileSystem) async {
  final pubspecFile = fileSystem
      .directory(Uri.parse(root.uri))
      .childFile('pubspec.yaml');
  if (!await pubspecFile.exists()) {
    return ProjectKind.unknown;
  }
  final pubspec = loadYaml(await pubspecFile.readAsString()) as Pubspec;

  if (pubspec.flutter != null ||
      pubspec.environment?.containsKey('flutter') == true ||
      pubspec.dependencies
          .followedBy(pubspec.devDependencies)
          .any((dep) => dep.sdk == 'flutter')) {
    return ProjectKind.flutter;
  }
  return ProjectKind.dart;
}

/// Runs [commandForRoot] in each of the project roots specified in the
/// [request], with [arguments].
///
/// These [commandForRoot] plus [arguments] are passed directly to
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
  FutureOr<String> Function(Root, FileSystem, Sdk) commandForRoot =
      defaultCommandForRoot,
  List<String> arguments = const [],
  required String commandDescription,
  required FileSystem fileSystem,
  required ProcessManager processManager,
  required List<Root> knownRoots,
  List<String> defaultPaths = const <String>[],
  required Sdk sdk,
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

  final outputs = <Content>[];
  for (var rootConfig in rootConfigs) {
    final result = await runCommandInRoot(
      request,
      rootConfig: rootConfig,
      commandForRoot: commandForRoot,
      arguments: arguments,
      commandDescription: commandDescription,
      fileSystem: fileSystem,
      processManager: processManager,
      knownRoots: knownRoots,
      defaultPaths: defaultPaths,
      sdk: sdk,
    );
    if (result.isError == true) return result;
    outputs.addAll(result.content);
  }
  return CallToolResult(content: outputs);
}

/// Runs [commandForRoot] in a single project root specified in the
/// [request], with [arguments].
///
/// If [rootConfig] is passed, this will be used to read the root configuration,
/// otherwise it is read directly off of `request.arguments`.
///
/// These [commandForRoot] plus [arguments] are passed directly to
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
Future<CallToolResult> runCommandInRoot(
  CallToolRequest request, {
  Map<String, Object?>? rootConfig,
  FutureOr<String> Function(Root, FileSystem, Sdk) commandForRoot =
      defaultCommandForRoot,
  List<String> arguments = const [],
  required String commandDescription,
  required FileSystem fileSystem,
  required ProcessManager processManager,
  required List<Root> knownRoots,
  List<String> defaultPaths = const <String>[],
  required Sdk sdk,
}) async {
  rootConfig ??= request.arguments;
  final rootUriString = rootConfig?[ParameterNames.root] as String?;
  if (rootUriString == null) {
    // This shouldn't happen based on the schema, but handle defensively.
    return CallToolResult(
      content: [
        TextContent(text: 'Invalid root configuration: missing `root` key.'),
      ],
      isError: true,
    );
  }

  final root = _findRoot(rootUriString, knownRoots);
  if (root == null) {
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
  final projectRoot = fileSystem.directory(rootUri);

  final commandWithPaths = <String>[
    await commandForRoot(root, fileSystem, sdk),
    ...arguments,
  ];
  final paths =
      (rootConfig?[ParameterNames.paths] as List?)?.cast<String>() ??
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
  return CallToolResult(
    content: [
      TextContent(text: '$commandDescription in ${projectRoot.path}:\n$output'),
    ],
  );
}

/// Returns 'dart' or 'flutter' based on the pubspec contents.
///
/// Throws an [ArgumentError] if there is no pubspec.
Future<String> defaultCommandForRoot(
  Root root,
  FileSystem fileSystem,
  Sdk sdk,
) async => switch (await inferProjectKind(root, fileSystem)) {
  ProjectKind.dart => sdk.dartExecutablePath,
  ProjectKind.flutter => sdk.flutterExecutablePath,
  ProjectKind.unknown =>
    throw ArgumentError.value(
      root.uri,
      'root.uri',
      'Unknown project kind at root ${root.uri}. All projects must have a '
          'pubspec.',
    ),
};

/// Returns whether or not [rootUri] is an allowed root, either exactly matching
/// or under on of the [knownRoots].
Root? _findRoot(String rootUri, List<Root> knownRoots) {
  for (final root in knownRoots) {
    final knownRootUri = Uri.parse(root.uri);
    final resolvedRoot = knownRootUri.resolve(rootUri).toString();
    if (root.uri == resolvedRoot || p.isWithin(root.uri, resolvedRoot)) {
      return root;
    }
  }
  return null;
}

/// The schema for the `roots` parameter for any tool that accepts it.
ListSchema rootsSchema({bool supportsPaths = false}) => Schema.list(
  title: 'All projects roots to run this tool in.',
  items: Schema.object(
    properties: {
      ParameterNames.root: rootSchema,
      if (supportsPaths)
        ParameterNames.paths: Schema.list(
          title:
              'Paths to run this tool on. Must resolve to a path that is '
              'within the "root".',
          items: Schema.string(),
        ),
    },
    required: [ParameterNames.root],
  ),
);

final rootSchema = Schema.string(
  title: 'The file URI of the project root to run this tool in.',
  description:
      'This must be equal to or a subdirectory of one of the roots '
      'allowed by the client. Must be a URI with a `file:` '
      'scheme (e.g. file:///absolute/path/to/root).',
);

/// Very thin extension type for a pubspec just containing what we need.
///
/// We assume a valid pubspec.
extension type Pubspec(Map<dynamic, dynamic> _value) {
  Iterable<Dependency> get dependencies =>
      (_value['dependencies'] as Map<dynamic, dynamic>?)?.values
          .cast<Dependency>() ??
      [];
  Iterable<Dependency> get devDependencies =>
      (_value['dev_dependencies'] as Map<dynamic, dynamic>?)?.values
          .cast<Dependency>() ??
      [];

  Map<dynamic, dynamic>? get environment =>
      _value['environment'] as Map<dynamic, dynamic>?;

  Map<dynamic, dynamic>? get flutter =>
      _value['flutter'] as Map<dynamic, dynamic>?;
}

/// An entry in `dependencies`, `dev_dependencies`, etc.
///
/// These might be [String] or [Map] types.
extension type Dependency(Object? _value) {
  /// If this is an `sdk` dependency, return that sdk, otherwise `null`.
  String? get sdk => _value is Map ? _value['sdk'] as String? : null;
}
