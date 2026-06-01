import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import '../core/dialog_support.dart';
import '../core/migration.dart';

/// Custom CommandRunner that handles global options and runs migrations before commands.
class SkillsCommandRunner extends CommandRunner<void> {
  final DialogSupport? dialogSupport;

  SkillsCommandRunner(super.executableName, super.description,
      {this.dialogSupport}) {
    argParser.addOption(
      'directory',
      abbr: 'C',
      help: 'Run as if in this directory (default: current directory).',
    );
  }

  @override
  Future<void> run(Iterable<String> args) async {
    final argResults = parse(args);

    final dir = argResults.option('directory');
    final rootPath =
        dir != null ? p.normalize(p.absolute(dir)) : Directory.current.path;

    if (!argResults.flag('help')) {
      await runMigrations(rootPath, dialogSupport);
    }

    return runCommand(argResults);
  }
}
