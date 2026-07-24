// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:skills/src/agent/agent.dart';
import 'package:skills/src/core/dialog_support.dart';
import 'package:skills/src/core/git_repos.dart';
import 'package:skills/src/core/package_resolver.dart';
import 'package:skills/src/core/skill_installer.dart';
import 'package:skills/src/core/workspace_resolver.dart';
import 'package:skills/src/models/global_config.dart';
import 'package:skills/src/models/skill_manifest.dart';

/// Checks if a global [GitRepo] has active skill install files recorded on
/// disk.
///
/// This check only applies to global repositories, whose installation paths are
/// recorded in [GitRepo.installs].
Future<bool> _hasActiveGlobalInstallsOnDisk(GitRepo repo) async {
  for (final path in repo.installs) {
    if (await File(path).exists() || await Directory(path).exists()) {
      return true;
    }
  }
  return false;
}

/// Checks if any installed skill in [manifest] belongs to [cloneUrl].
bool _hasActiveInstallsInManifest({
  required String cloneUrl,
  required SkillManifest manifest,
}) {
  for (final agentName in manifest.allAgents) {
    final entry = manifest.sourceUrisForAgent(agentName)[cloneUrl];
    if (entry != null && entry.skills.isNotEmpty) {
      return true;
    }
  }
  return false;
}

/// Prunes skills whose package dependencies are no longer in the workspace,
/// and cleans up unused git repository sources in local and global configs.
Future<void> pruneSkills({
  required WorkspaceLayout workspace,
  required Logger logger,
  DialogSupport? dialogSupport,
  List<Agent>? targetAgents,
  bool quietIfNothingToPrune = false,
  bool allFlag = false,
}) async {
  if (dialogSupport == null && !allFlag) {
    return;
  }

  final rootPath = workspace.rootPath;
  final packages = await PackageResolver.resolveWorkspace(workspace);
  final referencedNames = packages.map((p) => p.name).toSet();

  var manifest = await SkillManifest.loadOrEmptyFromRoot(rootPath);
  final globalConfigFile = File(GlobalConfig.globalPath);
  var globalConfig = await GlobalConfig.loadOrEmpty(globalConfigFile);

  if (manifest.isEmpty && globalConfig.gitRepos.isEmpty) {
    if (!quietIfNothingToPrune) {
      logger.info('No managed skills found.');
    }
    return;
  }

  final List<Agent> agentsToProcess;
  if (targetAgents != null && targetAgents.isNotEmpty) {
    agentsToProcess = targetAgents;
  } else {
    agentsToProcess = manifest.allAgents
        .map((name) => Agent.fromCliName(name))
        .whereType<Agent>()
        .toList();
  }

  final installer = SkillInstaller(dialogSupport);
  var totalRemoved = 0;
  final prunedPackages = <String>{};
  var totalGitSourcesRemoved = 0;

  for (final agent in agentsToProcess) {
    final sourceEntries = manifest.sourceUrisForAgent(agent.cliName);

    final unreferencedPackages = sourceEntries.keys
        .where(
          (uri) =>
              uri.startsWith('package:') &&
              !referencedNames.contains(uri.substring('package:'.length)),
        )
        .toSet();

    final emptyLocalGitSources = sourceEntries.entries
        .where((e) => !e.key.startsWith('package:') && e.value.skills.isEmpty)
        .map((e) => e.key)
        .toSet();

    final candidates = [...unreferencedPackages, ...emptyLocalGitSources]
      ..sort();
    if (candidates.isEmpty) continue;

    final Set<String> selectedItems;
    if (!allFlag) {
      final selectedIndices = await dialogSupport!.showMultiSelectDialog(
        candidates,
        title:
            'Select packages and local git sources to prune for '
            '${agent.cliName}:',
        initialSelected: {for (var i = 0; i < candidates.length; i++) i},
      );
      if (selectedIndices == null || selectedIndices.isEmpty) {
        continue;
      }
      selectedItems = selectedIndices.map((i) => candidates[i]).toSet();
    } else {
      selectedItems = candidates.toSet();
    }

    final pkgsToPrune = selectedItems
        .where((item) => item.startsWith('package:'))
        .toSet();
    final localGitToPrune = selectedItems
        .where((item) => !item.startsWith('package:'))
        .toSet();

    if (pkgsToPrune.isNotEmpty) {
      final result = await installer.removeSkillsForIde(
        agent: agent,
        rootPath: rootPath,
        manifest: manifest,
        sourceUris: pkgsToPrune,
      );
      manifest = result.manifest;
      totalRemoved += result.removedCount;
      prunedPackages.addAll(pkgsToPrune);
      for (final info in result.removed) {
        logger.info('  [${info.agentName}] Removed ${info.skillName}');
      }
    }

    for (final uri in localGitToPrune) {
      manifest = manifest.withoutSourceUri(agent.cliName, uri);
      totalGitSourcesRemoved++;
      logger.info('  [${agent.cliName}] Removed empty local git source "$uri"');
    }
  }

  // Handle global repos with no active installations.
  if (globalConfig.gitRepos.isNotEmpty) {
    var updatedRepos = globalConfig.gitRepos;
    for (final repo in globalConfig.gitRepos) {
      final activeOnDisk = await _hasActiveGlobalInstallsOnDisk(repo);
      final activeInManifest = _hasActiveInstallsInManifest(
        cloneUrl: repo.cloneUrl,
        manifest: manifest,
      );
      if (activeOnDisk || activeInManifest) continue;

      final bool removeGlobal;
      if (!allFlag) {
        final selection = await dialogSupport!.showSingleSelectDialog(
          const ['Yes', 'No'],
          title:
              'Remove global git source "${repo.cloneUrl}" which has no '
              'skills installed?',
        );
        removeGlobal = selection == 0;
      } else {
        removeGlobal = true;
      }

      if (removeGlobal) {
        updatedRepos = updatedRepos
            .where((r) => r.cloneUrl != repo.cloneUrl)
            .toList();
        totalGitSourcesRemoved++;
        logger.info('Removed global git source "${repo.cloneUrl}".');
      }
    }
    if (updatedRepos.length != globalConfig.gitRepos.length) {
      globalConfig = GlobalConfig(
        gitRepos: updatedRepos,
        neverPromptForSuggestedSkills:
            globalConfig.neverPromptForSuggestedSkills,
      );
      await globalConfig.save(globalConfigFile);
    }
  }

  await manifest.save(File(SkillManifest.pathIn(rootPath)));
  if (manifest.isEmpty) {
    await SkillManifest.cleanup(rootPath);
  }

  if (totalRemoved == 0 && totalGitSourcesRemoved == 0) {
    if (!quietIfNothingToPrune) {
      logger.info('No skills to prune.');
    }
  } else if (totalRemoved > 0) {
    logger.info(
      'Pruned $totalRemoved skill(s) from ${prunedPackages.length} package(s).',
    );
  }
}
