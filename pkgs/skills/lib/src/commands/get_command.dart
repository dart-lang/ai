import 'package:args/command_runner.dart';
import 'package:skills/src/commands/get_skills.dart';
import 'package:skills/src/core/dialog_support.dart';
import 'package:skills/src/core/git_repos.dart';

import '../core/git_runner.dart';
import 'options.dart';
import 'skills_command.dart';

/// Installs skills from package dependencies.
class GetCommand extends SkillsCommand {
  @override
  final String name = 'get';

  @override
  final String description = 'Install skills from package dependencies.';

  final DialogSupport? _dialogSupport;
  final GitRunner? _gitRunner;

  GetCommand({DialogSupport? dialogSupport, GitRunner? gitRunner})
    : _dialogSupport = dialogSupport,
      _gitRunner = gitRunner {
    addIdeOption(argParser);
    argParser
      ..addMultiOption(
        'package',
        abbr: 'p',
        help: 'Install/update skills from these packages only.',
      )
      ..addMultiOption('git', help: 'Update skills from these git repos only.')
      ..addMultiOption(
        'skill',
        abbr: 's',
        help: 'Only install these specific skills.',
      )
      ..addFlag(
        'all',
        abbr: 'a',
        help: 'Install/update all skills from all sources.',
        negatable: false,
      );
  }

  GitRunner get _effectiveGitRunner => _gitRunner ?? const GitRunner();

  @override
  Future<void> run() async {
    final argResults = this.argResults!;
    final workspace = await resolveWorkspace();
    final rootPath = workspace.rootPath;

    if (workspace.isWorkspace) {
      logger.info(
        'Detected workspace with ${workspace.packages.length} packages.',
      );
    }

    final ides = await resolveIdes(
      argResults: argResults,
      projectPath: rootPath,
      dialogSupport: _dialogSupport,
    );

    final packageUris = argResults
        .multiOption('package')
        .map((p) => 'package:$p');
    final gitUris = argResults
        .multiOption('git')
        .map((arg) => parseGitRepoArg(arg, usage).cloneUrl);
    final sourceUris = {...packageUris, ...gitUris};
    final skillNames = argResults.multiOption('skill').toSet();
    final allFlag = argResults.flag('all');
    if (skillNames.isNotEmpty && allFlag) {
      throw UsageException(
        '--all and --skill are mutually exclusive arguments, please provide '
        'only one',
        usage,
      );
    }

    await getSkills(
      ides: ides,
      logger: logger,
      workspace: workspace,
      dialogSupport: _dialogSupport,
      gitRunner: _effectiveGitRunner,
      usage: usage,
      sourceUris: sourceUris,
      skillNames: skillNames,
      allFlag: allFlag,
    );
  }
}
