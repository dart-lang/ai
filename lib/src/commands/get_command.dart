import 'dart:io';

import 'package:skills/src/commands/get_skills.dart';

import '../core/git_runner.dart';
import 'options.dart';
import 'skills_command.dart';

/// Installs skills from package dependencies.
class GetCommand extends SkillsCommand {
  @override
  final String name = 'get';

  @override
  final String description = 'Install skills from package dependencies.';

  final GitRunner? _gitRunner;

  GetCommand({GitRunner? gitRunner}) : _gitRunner = gitRunner {
    addIdeOption(argParser);
  }

  GitRunner get _effectiveGitRunner => _gitRunner ?? const GitRunner();

  @override
  Future<void> run() async {
    final workspace = await resolveWorkspace();
    final rootPath = workspace.rootPath;

    if (workspace.isWorkspace) {
      stdout.writeln(
        'Detected workspace with ${workspace.packages.length} packages.',
      );
    }

    final ides = resolveIdes(argResults: argResults, projectPath: rootPath);

    await getSkills(
      ides: ides,
      workspace: workspace,
      gitRunner: _effectiveGitRunner,
      usage: usage,
      packageName: packageNameArg,
    );
  }
}
