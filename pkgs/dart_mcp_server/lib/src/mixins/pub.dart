// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/server.dart';
import 'package:meta/meta.dart';
import 'package:yaml/yaml.dart';

import '../features_configuration.dart';
import '../utils/analytics.dart';
import '../utils/cli_utils.dart';
import '../utils/file_system.dart';
import '../utils/names.dart';
import '../utils/process_manager.dart';
import '../utils/sdk.dart';

/// Mix this in to any MCPServer to add support for running Pub commands like
/// like `pub add` and `pub get`.
///
/// See [SupportedPubCommand] for the set of currently supported pub commands.
///
/// The MCPServer must already have the [ToolsSupport] and [LoggingSupport]
/// mixins applied.
base mixin PubSupport on ToolsSupport, LoggingSupport, RootsTrackingSupport
    implements ProcessManagerSupport, FileSystemSupport, SdkSupport {
  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    try {
      return super.initialize(request);
    } finally {
      if (supportsRoots) {
        registerTool(pubTool, _runDartPubTool);
      }
    }
  }

  @visibleForTesting
  static final List<Tool> allTools = [pubTool];

  /// Implementation of the [pubTool].
  Future<CallToolResult> _runDartPubTool(CallToolRequest request) async {
    final command = request.arguments![ParameterNames.command] as String;
    final matchingCommand = SupportedPubCommand.fromName(command);
    if (matchingCommand == null) {
      return CallToolResult(
        content: [
          TextContent(
            text:
                'Unsupported pub command `$command`. Currently, the supported '
                'commands are: '
                '${SupportedPubCommand.values.map((e) => e.name).join(', ')}',
          ),
        ],
        isError: true,
      )..failureReason ??= CallToolFailureReason.noSuchCommand;
    }

    final packageNames =
        (request.arguments?[ParameterNames.packageNames] as List?)
            ?.cast<String>();
    if (matchingCommand.requiresPackageNames &&
        (packageNames == null || packageNames.isEmpty)) {
      return CallToolResult(
        content: [
          TextContent(
            text:
                'Missing required argument `packageNames` for the `$command` '
                'command.',
          ),
        ],
        isError: true,
      )..failureReason ??= CallToolFailureReason.argumentError;
    }

    // The `packageNames` list is forwarded directly into the `dart pub` argv.
    // A caller (or an LLM acting on injected instructions) could otherwise
    // smuggle pub flags such as `--directory` here to operate on a path outside
    // the approved roots, or pass other unexpected arguments. Validate each
    // entry, and pass the remaining names after a `--` separator so pub's
    // argument parser always treats them as positional package descriptors.
    if (packageNames != null) {
      final invalid = packageNames.where((name) => !_isValidPackageEntry(name));
      if (invalid.isNotEmpty) {
        return CallToolResult(
          content: [
            TextContent(
              text:
                  'Invalid `packageNames` entries: ${invalid.join(', ')}. '
                  'Entries must be Dart package names or descriptors '
                  '(e.g. `my_pkg`, `dev:my_pkg`, `my_pkg:^1.0.0`).',
            ),
          ],
          isError: true,
        )..failureReason ??= CallToolFailureReason.argumentError;
      }
    }

    return runCommandInRoots(
      request,
      arguments: [
        'pub',
        command,
        if (packageNames != null && packageNames.isNotEmpty) '--',
        ...?packageNames,
      ],
      commandDescription: 'dart|flutter pub $command',
      processManager: processManager,
      knownRoots: await roots,
      fileSystem: fileSystem,
      sdk: sdk,
    );
  }

  static final pubTool =
      Tool(
          name: ToolNames.pub.name,
          description:
              'Runs a pub command for the given project roots, like `dart pub '
              'get` or `flutter pub add`.',
          annotations: ToolAnnotations(title: 'pub', readOnlyHint: false),
          inputSchema: Schema.object(
            properties: {
              ParameterNames.command: Schema.string(
                title: 'The pub subcommand to run.',
                // ignore: deprecated_member_use
                enumValues: SupportedPubCommand.values
                    .map<String>((e) => e.name)
                    .toList(),
                description: SupportedPubCommand.commandDescriptions,
              ),
              ParameterNames.packageNames: Schema.list(
                title: 'The package names to run the command for.',
                description:
                    'This is required for the '
                    '${SupportedPubCommand.listAllThatRequirePackageName} '
                    'commands.',
                items: Schema.string(
                  title: 'A package to run the command for.',
                ),
              ),
              ParameterNames.roots: rootsSchema(),
            },
            required: [ParameterNames.command],
            additionalProperties: false,
          ),
        )
        ..categories = [FeatureCategory.cli, FeatureCategory.packageDeps]
        ..enabledByDefault = true;
}

/// The set of supported `dart pub` subcommands.
enum SupportedPubCommand {
  add(
    requiresPackageNames: true,
    description: '''Add package dependencies.
  - To add a package normally (typical): "pkg_name"
  - Git reference: "pkg_name:{git:{url: https://github.com/pkg_name/pkg_name.git, ref: branch, path: subdir}}"
    - ref and path are optional.
  - From local path: "pkg_name:{path: ../pkg_name}"
  - Dev Dependency: "dev:pkg_name"
  - Dependency override: "override:pkg_name:1.0.0"
 ''',
  ),

  deps(description: 'Print the dependency tree of the current package.'),

  get(
    description: "Fetch the current package's dependencies and install them.",
  ),

  outdated(
    description: 'Analyze dependencies to find which ones can be upgraded.',
  ),

  // This is supported in a simplified form: `dart pub remove <package-name>`.
  remove(
    requiresPackageNames: true,
    description: 'Removes specified dependencies from `pubspec.yaml`.',
  ),

  upgrade(
    description:
        "Upgrade the current package's dependencies to latest versions.",
  );

  const SupportedPubCommand({
    this.requiresPackageNames = false,
    required this.description,
  });

  final bool requiresPackageNames;

  /// The description to use in the subcommand help.
  final String description;

  static SupportedPubCommand? fromName(String name) {
    for (final command in SupportedPubCommand.values) {
      if (command.name == name) {
        return command;
      }
    }
    return null;
  }

  static String get listAll {
    return _writeCommandsAsList(SupportedPubCommand.values);
  }

  static String get listAllThatRequirePackageName {
    return _writeCommandsAsList(
      SupportedPubCommand.values.where((c) => c.requiresPackageNames).toList(),
    );
  }

  static String get commandDescriptions {
    return 'Available subcommands:\n${_getDescriptions(values)}';
  }

  static String _getDescriptions(Iterable<SupportedPubCommand> commands) {
    final buffer = StringBuffer();
    for (final command in commands) {
      final commandName = command.name;
      final description = command.description;
      if (description.isNotEmpty) {
        buffer.writeln('- `$commandName`: $description');
      }
    }
    return buffer.toString();
  }

  static String _writeCommandsAsList(List<SupportedPubCommand> commands) {
    final buffer = StringBuffer();
    for (var i = 0; i < commands.length; i++) {
      final commandName = commands[i].name;
      buffer.write('`$commandName`');
      if (i < commands.length - 2) {
        buffer.write(', ');
      } else if (i == commands.length - 2) {
        buffer.write(', and ');
      }
    }
    return buffer.toString();
  }
}

/// Control characters, non-ASCII whitespace, and disallowed punctuation.
final _disallowedPackageChars = RegExp(
  r'[\x00-\x1F\x7F-\x9F\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F'
  r'''\u3000\uFEFF&|;`$%!()"'\\*?#]''',
);

final _packageNamePattern = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$');

final _separatorPattern = RegExp('[:@]');

/// Matches a SemVer version (`MAJOR.MINOR.PATCH` with optional suffixes).
const _semverPattern =
    r'\d+\.\d+\.\d+(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?'
    r'(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?';

/// Matches a version constraint (e.g. `^1.2.3`, `>=1.0.0 <2.0.0`, `any`) or
/// `pub upgrade` keyword (`latest`, `resolvable`).
final _versionDescriptorPattern = RegExp(
  '^(?:any|latest|resolvable|\\^ *$_semverPattern|'
  '(?:(?:<=?|>=?)? *$_semverPattern)(?: +(?:<=?|>=?)? *$_semverPattern)*)\$',
);

/// Allowed top-level keys in `pub add` YAML descriptors.
const _allowedDescriptorKeys = {'version', 'path', 'sdk', 'git', 'hosted'};

/// Whether [entry] is a valid `pub` package argument (e.g. `pkg`, `dev:pkg`,
/// `pkg:^1.0.0`, or `pkg:{path: ../pkg}`).
bool _isValidPackageEntry(String entry) {
  if (entry.isEmpty || _disallowedPackageChars.hasMatch(entry)) {
    return false;
  }

  var rest = entry;
  if (rest.startsWith('dev:')) {
    rest = rest.substring('dev:'.length);
  } else if (rest.startsWith('override:')) {
    rest = rest.substring('override:'.length);
  }

  final separatorIndex = rest.indexOf(_separatorPattern);
  if (separatorIndex == -1) {
    return _packageNamePattern.hasMatch(rest);
  }

  final packageName = rest.substring(0, separatorIndex);
  final descriptor = rest.substring(separatorIndex + 1);
  if (!_packageNamePattern.hasMatch(packageName) || descriptor.isEmpty) {
    return false;
  }

  if (descriptor.startsWith('{')) {
    return _isValidYamlDescriptor(descriptor);
  }
  return _versionDescriptorPattern.hasMatch(descriptor);
}

bool _isValidYamlDescriptor(String descriptor) {
  if (!descriptor.endsWith('}') ||
      descriptor.contains('<') ||
      descriptor.contains('>')) {
    return false;
  }
  final Object? parsed;
  try {
    parsed = loadYaml(descriptor);
  } on YamlException {
    return false;
  }
  if (parsed is! YamlMap || parsed.isEmpty) return false;
  if (!parsed.keys.every(_allowedDescriptorKeys.contains)) return false;
  return _hasValidDescriptorEntries(parsed, allowNestedMap: true);
}

bool _hasValidDescriptorEntries(YamlMap map, {required bool allowNestedMap}) {
  for (final entry in map.entries) {
    final key = entry.key;
    final value = entry.value;
    if (key is! String || !_packageNamePattern.hasMatch(key)) return false;
    if (value is YamlMap) {
      if (!allowNestedMap ||
          value.isEmpty ||
          !_hasValidDescriptorEntries(value, allowNestedMap: false)) {
        return false;
      }
      continue;
    }
    final stringValue = switch (value) {
      String() => value,
      num() => value.toString(),
      _ => null,
    };
    // Reject CLI flags and Git's `ext::` remote helper scheme, which resolves
    // regardless of case on case-insensitive file systems.
    if (stringValue == null ||
        stringValue.isEmpty ||
        stringValue.startsWith('-') ||
        stringValue.toLowerCase().startsWith('ext::')) {
      return false;
    }
    if (key == 'version' && !_versionDescriptorPattern.hasMatch(stringValue)) {
      return false;
    }
  }
  return true;
}
