// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/server.dart';

import '../utils/analytics.dart';
import '../utils/cli_utils.dart';
import '../utils/constants.dart';
import '../utils/file_system.dart';
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
    if (matchingCommand.requiresPackageNames && packageNames == null) {
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

    return runCommandInRoots(
      request,
      arguments: ['pub', command, if (packageNames != null) ...packageNames],
      commandDescription: 'dart|flutter pub $command',
      processManager: processManager,
      knownRoots: await roots,
      fileSystem: fileSystem,
      sdk: sdk,
    );
  }

  static final pubTool = Tool(
    name: 'pub',
    description:
        'Runs a pub command for the given project roots, like `dart pub '
        'get` or `flutter pub add`.',
    annotations: ToolAnnotations(title: 'pub', readOnlyHint: false),
    inputSchema: Schema.object(
      properties: {
        ParameterNames.command: Schema.string(
          title: 'The pub command to run.',
          description:
              'Currently only ${SupportedPubCommand.listAll} are supported.',
        ),
        ParameterNames.packageNames: Schema.list(
          title: 'The package names to run the command for.',
          description:
              'This is required for the '
              '${SupportedPubCommand.listAllThatRequirePackageName} commands. ',
          items: Schema.string(
            title: 'A package to run the command for.',
            description:
                'When used with "add", prefix with "dev:" to add the package '
                'as a dev dependency.',
          ),
        ),
        ParameterNames.roots: rootsSchema(),
      },
      required: [ParameterNames.command],
    ),
  );
}

/// The set of supported `dart pub` subcommands.
enum SupportedPubCommand {
  // This is supported in a simplified form: `dart pub add <package-name>`.
  // TODO(https://github.com/dart-lang/ai/issues/77): add support for adding
  //  dev dependencies.
  add(requiresPackageNames: true),

  get,

  // This is supported in a simplified form: `dart pub remove <package-name>`.
  remove(requiresPackageNames: true),

  upgrade;

  const SupportedPubCommand({this.requiresPackageNames = false});

  final bool requiresPackageNames;

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
