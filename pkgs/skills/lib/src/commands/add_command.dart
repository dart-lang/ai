import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:skills/src/commands/get_skills.dart';
import 'package:skills/src/models/skill_manifest.dart';

import '../core/dialog_support.dart';
import '../core/git_repos.dart';
import '../core/git_runner.dart';
import '../core/git_sync.dart';
import '../models/global_config.dart';

import 'options.dart';
import 'skills_command.dart';

/// Command to add a git repo as a skill source and install skills from it.
class AddCommand extends SkillsCommand {
  @override
  final String name = 'add';

  @override
  final String description =
      'Add a git repository as a skill source and install skills from it.';

  final DialogSupport? dialogSupport;
  final GitRunner gitRunner;

  AddCommand({this.dialogSupport, this.gitRunner = const GitRunner()}) {
    addAgentOption(argParser);
    argParser
      ..addFlag(
        'global',
        help: 'Install the skill(s) globally.',
        defaultsTo: false,
      )
      ..addMultiOption(
        'skill',
        abbr: 's',
        help: 'Install the specific skills only.',
      )
      ..addFlag(
        'all',
        abbr: 'a',
        help: 'Install all skills from the given git repo.',
        negatable: false,
      );
  }

  @override
  Future<void> run() async {
    final argResults = this.argResults!;
    final rest = argResults.rest;

    final gitRepos = rest.map((arg) => parseGitRepoArg(arg, usage));
    if (gitRepos.isEmpty) {
      throw UsageException(
        'Please provide at least one git url (or org/name) to add.',
        usage,
      );
    }
    final skillNames = argResults.multiOption('skill').toSet();
    final isGlobal = argResults.flag('global');
    final allFlag = argResults.flag('all');
    if (skillNames.isNotEmpty && allFlag) {
      throw UsageException(
        '--all and --skill are mutually exclusive arguments, please provide '
        'only one',
        usage,
      );
    }

    final workspace = await resolveWorkspace();
    final rootPath = workspace.rootPath;

    final agents = await resolveAgents(
      argResults: argResults,
      projectPath: rootPath,
      dialogSupport: dialogSupport,
    );
    if (agents.isEmpty) return;

    final validRepos = <GitRepo>[];
    if (await gitRunner.isAvailable) {
      final gitSync = GitSync(gitRunner: gitRunner, repos: gitRepos.toList());
      await gitSync.sync(rootPath, onProgress: logger.info);

      for (final repo in gitRepos) {
        final repoDir = Directory(gitRepoPath(rootPath, repo));
        if (await repoDir.exists()) {
          validRepos.add(repo);
        } else {
          logger.severe(
            'Failed to clone or sync git repository: ${repo.cloneUrl}',
          );
        }
      }
      if (validRepos.isEmpty) return;
    } else {
      validRepos.addAll(gitRepos);
    }

    if (isGlobal) {
      // Add the entry to the global config if not present.
      final globalConfigPath = GlobalConfig.globalPath;
      final globalConfigFile = File(globalConfigPath);
      var globalConfig = await GlobalConfig.loadOrEmpty(globalConfigFile);

      for (var repo in validRepos) {
        if (!globalConfig.gitRepos.any((r) => r.cloneUrl == repo.cloneUrl)) {
          globalConfig = globalConfig.withGitRepo(repo);
          logger.info('Added ${repo.cloneUrl} to global config.');
        }
      }
      await globalConfig.save(globalConfigFile);
    } else {
      // Add the entries to the local config if not present.
      final localFile = manifestFile(workspace.rootPath);
      var manifest = await SkillManifest.loadOrEmpty(localFile);
      for (var agent in agents) {
        for (var repo in validRepos) {
          if (manifest
              .sourceUrisForAgent(agent.cliName)
              .containsKey(repo.cloneUrl)) {
            continue;
          }
          manifest = manifest.withSourceUri(
            agent.cliName,
            repo.cloneUrl,
            SkillsEntry(),
          );
        }
      }
      await manifest.save(localFile);
    }

    await getSkills(
      agents: agents,
      logger: logger,
      workspace: workspace,
      dialogSupport: dialogSupport,
      usage: usage,
      sourceUris: {for (var repo in validRepos) repo.cloneUrl},
      skillNames: skillNames,
      allFlag: allFlag,
      gitRunner: gitRunner,
    );
  }
}
