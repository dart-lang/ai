// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:dart_mcp/server.dart';

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
    registerTool(dartPubTool, _runDartPubTool);
    return super.initialize(request);
  }

  /// Implementation of the [dartFixTool].
  Future<CallToolResult> _runDartFixTool(CallToolRequest request) async {
    return _runDartCommandInRoots(
      request,
      commandDescription: 'dart fix',
      commandArgs: ['fix', '--apply'],
    );
  }

  /// Implementation of the [dartFormatTool].
  Future<CallToolResult> _runDartFormatTool(CallToolRequest request) async {
    return _runDartCommandInRoots(
      request,
      commandDescription: 'dart format',
      commandArgs: ['format'],
      defaultPaths: ['.'],
    );
  }

  /// Implementation of the [dartPubTool].
  Future<CallToolResult> _runDartPubTool(CallToolRequest request) async {
    final command = request.arguments?['command'] as String?;
    if (command == null) {
      return CallToolResult(
        content: [TextContent(text: 'Missing required argument `command`.')],
        isError: true,
      );
    }
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
      );
    }

    final packageName = request.arguments?['packageName'] as String?;
    if (matchingCommand.requiresPackageName && packageName == null) {
      return CallToolResult(
        content: [
          TextContent(
            text:
                'Missing required argument `packageName` for the `$command` '
                'command.',
          ),
        ],
        isError: true,
      );
    }

    return _runDartCommandInRoots(
      request,
      commandDescription: 'dart pub $command',
      commandArgs: ['pub', command, if (packageName != null) packageName],
    );
  }

  /// Helper to run a dart command in multiple project roots.
  ///
  /// [defaultPaths] may be specified if one or more path arguments are required
  /// for the dart command (e.g. `dart format <default paths>`).
  Future<CallToolResult> _runDartCommandInRoots(
    CallToolRequest request, {
    required String commandDescription,
    required List<String> commandArgs,
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

      final result = await processManager.run(
        ['dart', ...commandArgs],
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

  static final dartPubTool = Tool(
    name: 'dart_pub',
    description:
        'Runs a dart pub command for the given project roots, like `dart pub '
        'get` or `dart pub add`.',
    inputSchema: ObjectSchema(
      properties: {
        'command': StringSchema(
          title: 'The dart pub command to run.',
          description:
              'Currently only ${SupportedPubCommand.listAll} are supported.',
        ),
        'packageName': StringSchema(
          title: 'The package name to run the command for.',
          description:
              'This is required for the '
              '${SupportedPubCommand.listAllThatRequirePackageName} commands.',
        ),
        'roots': ListSchema(
          title: 'All projects roots to run the dart pub command in.',
          description:
              'These must match a root returned by a call to "listRoots".',
          items: ObjectSchema(
            properties: {
              'root': StringSchema(
                title:
                    'The URI of the project root to run the dart pub command '
                    'in.',
              ),
            },
            required: ['root'],
          ),
        ),
      },
      required: ['command', 'roots'],
    ),
  );

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

/// The set of supported `dart pub` subcommands.
enum SupportedPubCommand {
  // This is supported in a simplified form: `dart pub add <package-name>`.
  // TODO(https://github.com/dart-lang/ai/issues/77): add support for adding
  //  dev dependencies.
  add(requiresPackageName: true),

  get,

  // This is supported in a simplified form: `dart pub remove <package-name>`.
  remove(requiresPackageName: true),

  upgrade;

  const SupportedPubCommand({this.requiresPackageName = false});

  final bool requiresPackageName;

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
      SupportedPubCommand.values.where((c) => c.requiresPackageName).toList(),
    );
  }

  static String _writeCommandsAsList(List<SupportedPubCommand> commands) {
    final buffer = StringBuffer();
    for (var i = 0; i < commands.length; i++) {
      final commandName = commands[i].name;
      buffer.write('`$commandName`');
      if (i < commands.length - 2) {
        buffer.write(', ');
      } else if (i == commands.length - 2) {
        buffer.write(' and ');
      }
    }
    return buffer.toString();
  }
}
