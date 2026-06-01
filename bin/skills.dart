import 'dart:io' as io;

import 'package:args/command_runner.dart';
import 'package:cli_util/windows_compatibility.dart';
import 'package:io/ansi.dart';
import 'package:io/io.dart';
import 'package:logging/logging.dart';
import 'package:skills/skills.dart';
import 'package:skills/src/commands/prune_command.dart';
import 'package:skills/src/commands/registry_command.dart';
import 'package:skills/src/commands/skills_command_runner.dart';
import 'package:skills/src/core/exceptions.dart';

Future<void> main(List<String> arguments) async {
  Logger.root.onRecord.listen((log) {
    final color = switch (log) {
      _ when log.level >= Level.SEVERE => red,
      _ when log.level >= Level.WARNING => yellow,
      _ => null,
    };
    io.stdout.writeln(wrapWith(log.message, [if (color != null) color]));
  });

  DialogSupport? dialogSupport;
  // TODO: Remove this when https://github.com/dart-lang/tools/pull/2396
  // is release.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedStdIn? sharedStdIn;
  if (io.stdin.hasTerminal && io.stdout.hasTerminal) {
    sharedStdIn =
        SharedStdIn(io.Platform.isWindows ? Win32AnsiStdin() : io.stdin);
    dialogSupport = CliUtilDialogSupport(sharedStdIn);
  }
  try {
    final runner = SkillsCommandRunner(
      'skills',
      'Manage AI agent skills for Dart/Flutter packages.',
      dialogSupport: dialogSupport,
    )
      ..addCommand(GetCommand(dialogSupport: dialogSupport))
      ..addCommand(ListCommand())
      ..addCommand(PruneCommand(dialogSupport: dialogSupport))
      ..addCommand(RemoveCommand(dialogSupport: dialogSupport))
      ..addCommand(RegistryCommand(dialogSupport: dialogSupport));

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
}
