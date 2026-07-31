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

const _packagePrefix = 'package:';

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
    if (!quietIfNothingToPrune) {
      logger.info(
        'No interactive terminal detected and --all was not specified. '
        'Aborting prune. Run with --all to prune automatically.',
      );
    }
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
    final result = await _pruneSkillsForAgent(
      agent: agent,
      manifest: manifest,
      referencedNames: referencedNames,
      rootPath: rootPath,
      installer: installer,
      logger: logger,
      dialogSupport: dialogSupport,
      allFlag: allFlag,
    );
    if (result == null) return;
    manifest = result.manifest;
    totalRemoved += result.removedCount;
    prunedPackages.addAll(result.prunedPackages);
    totalGitSourcesRemoved += result.gitSourcesRemovedCount;
  }

  await manifest.save(File(SkillManifest.pathIn(rootPath)));

  // Handle global repos with no active installations.
  if (globalConfig.gitRepos.isNotEmpty) {
    final candidateGlobalRepos = <GitRepo>[];
    for (final repo in globalConfig.gitRepos) {
      final activeOnDisk = await _hasActiveGlobalInstallsOnDisk(repo);
      if (!activeOnDisk) {
        candidateGlobalRepos.add(repo);
      }
    }

    if (candidateGlobalRepos.isNotEmpty) {
      final Set<GitRepo> reposToRemove;
      if (!allFlag) {
        final options = candidateGlobalRepos.map((r) => r.cloneUrl).toList();
        final selectedIndices = await dialogSupport!.showMultiSelectDialog(
          options,
          title: 'Select global git sources to remove:',
          initialSelected: {for (var i = 0; i < options.length; i++) i},
        );
        if (selectedIndices == null) {
          logger.info('Prune aborted by user.');
          return;
        }
        if (selectedIndices.isEmpty) {
          reposToRemove = const {};
        } else {
          reposToRemove = selectedIndices
              .map((i) => candidateGlobalRepos[i])
              .toSet();
        }
      } else {
        reposToRemove = candidateGlobalRepos.toSet();
      }

      if (reposToRemove.isNotEmpty) {
        totalGitSourcesRemoved += reposToRemove.length;
        for (final repo in reposToRemove) {
          logger.info('Removed global git source "${repo.cloneUrl}".');
        }
        globalConfig = globalConfig.withoutGitRepos(reposToRemove);
        await globalConfig.save(globalConfigFile);
      }
    }
  }

  if (manifest.isEmpty) {
    await SkillManifest.cleanup(rootPath);
  }

  if (totalRemoved == 0 && totalGitSourcesRemoved == 0) {
    if (!quietIfNothingToPrune) {
      logger.info('No skills to prune.');
    }
  } else {
    final summaryParts = <String>[];
    if (totalRemoved > 0) {
      summaryParts.add(
        'Pruned $totalRemoved skill(s) from ${prunedPackages.length} package(s).',
      );
    }
    if (totalGitSourcesRemoved > 0) {
      summaryParts.add('Removed $totalGitSourcesRemoved empty git source(s).');
    }
    logger.info(summaryParts.join(' '));
  }
}

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

typedef _AgentPruneResult = ({
  SkillManifest manifest,
  int removedCount,
  Set<String> prunedPackages,
  int gitSourcesRemovedCount,
});

Future<_AgentPruneResult?> _pruneSkillsForAgent({
  required Agent agent,
  required SkillManifest manifest,
  required Set<String> referencedNames,
  required String rootPath,
  required SkillInstaller installer,
  required Logger logger,
  DialogSupport? dialogSupport,
  required bool allFlag,
}) async {
  final sourceEntries = manifest.sourceUrisForAgent(agent.cliName);

  final unreferencedPackages = sourceEntries.keys
      .where(
        (uri) =>
            uri.startsWith(_packagePrefix) &&
            !referencedNames.contains(uri.substring(_packagePrefix.length)),
      )
      .toSet();

  final emptyLocalGitSources = sourceEntries.entries
      .where((e) => !e.key.startsWith(_packagePrefix) && e.value.skills.isEmpty)
      .map((e) => e.key)
      .toSet();

  final candidates = [...unreferencedPackages, ...emptyLocalGitSources]..sort();
  if (candidates.isEmpty) {
    return (
      manifest: manifest,
      removedCount: 0,
      prunedPackages: const <String>{},
      gitSourcesRemovedCount: 0,
    );
  }

  final Set<String> selectedItems;
  if (!allFlag) {
    final selectedIndices = await dialogSupport!.showMultiSelectDialog(
      candidates,
      title:
          'Select packages and local git sources to prune for '
          '${agent.cliName}:',
      initialSelected: {for (var i = 0; i < candidates.length; i++) i},
    );
    if (selectedIndices == null) {
      logger.info('Prune aborted by user.');
      return null;
    }
    if (selectedIndices.isEmpty) {
      return (
        manifest: manifest,
        removedCount: 0,
        prunedPackages: const <String>{},
        gitSourcesRemovedCount: 0,
      );
    }
    selectedItems = selectedIndices.map((i) => candidates[i]).toSet();
  } else {
    selectedItems = candidates.toSet();
  }

  final pkgsToPrune = <String>{};
  final localGitToPrune = <String>{};
  for (final item in selectedItems) {
    if (item.startsWith(_packagePrefix)) {
      pkgsToPrune.add(item);
    } else {
      localGitToPrune.add(item);
    }
  }

  var updatedManifest = manifest;
  var removedCount = 0;
  var gitSourcesRemovedCount = 0;

  if (pkgsToPrune.isNotEmpty) {
    final result = await installer.removeSkillsForAgent(
      agent: agent,
      rootPath: rootPath,
      manifest: updatedManifest,
      sourceUris: pkgsToPrune,
    );
    updatedManifest = result.manifest;
    removedCount += result.removedCount;
    for (final info in result.removed) {
      logger.info('  [${info.agentName}] Removed ${info.skillName}');
    }
  }

  for (final uri in localGitToPrune) {
    updatedManifest = updatedManifest.withoutSourceUri(agent.cliName, uri);
    gitSourcesRemovedCount++;
    logger.info('  [${agent.cliName}] Removed empty local git source "$uri"');
  }

  return (
    manifest: updatedManifest,
    removedCount: removedCount,
    prunedPackages: pkgsToPrune,
    gitSourcesRemovedCount: gitSourcesRemovedCount,
  );
}
