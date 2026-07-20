// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io' as io;

import 'package:args/command_runner.dart';
import 'package:cli_util/windows_compatibility.dart';
import 'package:io/ansi.dart';
import 'package:io/io.dart';
import 'package:logging/logging.dart';
import 'package:skills/skills.dart';
import 'package:skills/src/commands/create_command.dart';
import 'package:skills/src/commands/prune_command.dart';
import 'package:skills/src/commands/add_command.dart';
import 'package:skills/src/commands/skills_command_runner.dart';
import 'package:skills/src/core/analytics.dart';
import 'package:skills/src/core/exceptions.dart';
import 'package:unified_analytics/unified_analytics.dart';

Future<void> main(List<String> arguments) async {
  DashTool? tool;
  if (io.Platform.environment[DashEnvVar.tool.name] case final toolEnv?) {
    try {
      tool = DashTool.fromLabel(toolEnv);
    } catch (e) {
      // Ignore errors, but don't track analytics for unrecognized tools.
    }
  }

  final analyticsInstance = tool != null
      ? Analytics(
          tool: tool,
          dartVersion: parseDartSDKVersion(io.Platform.version),
        )
      : null;

  try {
    await runWithAnalytics(analyticsInstance, () async {
      Logger.root.onRecord.listen((log) {
        final color = switch (log) {
          _ when log.level >= Level.SEVERE => red,
          _ when log.level >= Level.WARNING => yellow,
          _ => null,
        };
        io.stdout.writeln(wrapWith(log.message, [?color]));
      });

      DialogSupport? dialogSupport;
      // TODO: Remove this when https://github.com/dart-lang/tools/pull/2396
      // is release.
      // ignore: invalid_use_of_visible_for_testing_member
      SharedStdIn? sharedStdIn;
      if (io.stdin.hasTerminal && io.stdout.hasTerminal) {
        sharedStdIn = SharedStdIn(
          io.Platform.isWindows ? Win32AnsiStdin() : io.stdin,
        );
        dialogSupport = CliUtilDialogSupport(sharedStdIn);
      }
      try {
        final runner =
            SkillsCommandRunner(
                'skills',
                'Manage AI agent skills for Dart/Flutter packages.',
                dialogSupport: dialogSupport,
              )
              ..addCommand(GetCommand(dialogSupport: dialogSupport))
              ..addCommand(ListCommand())
              ..addCommand(PruneCommand(dialogSupport: dialogSupport))
              ..addCommand(RemoveCommand(dialogSupport: dialogSupport))
              ..addCommand(AddCommand(dialogSupport: dialogSupport))
              ..addCommand(CreateCommand());

        try {
          await runner.run(arguments);
        } on UsageException catch (e) {
          print(e);
        } on UserAbortException catch (e) {
          print(e);
        }
      } finally {
        await sharedStdIn?.terminate();
      }
    });
  } finally {
    await analyticsInstance?.close();
  }
}
