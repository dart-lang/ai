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

/// Checks if a global [GitRepo] has any active skill installations on disk
/// or in the local workspace [manifest].
Future<bool> _hasActiveInstalls({
  required GitRepo repo,
  required SkillManifest manifest,
}) async {
  for (final path in repo.installs) {
    if (await File(path).exists() || await Directory(path).exists()) {
      return true;
    }
  }
  for (final agentName in manifest.allAgents) {
    final entry = manifest.sourceUrisForAgent(agentName)[repo.cloneUrl];
    if (entry != null && entry.skills.isNotEmpty) {
      return true;
    }
  }
  return false;
}

/// Prunes skills whose package dependencies are no longer in the workspace,
/// and prompts to remove git repository sources in local and global configs that
/// have no installed skills.
Future<void> pruneSkills({
  required WorkspaceLayout workspace,
  required Logger logger,
  DialogSupport? dialogSupport,
  List<Agent>? targetAgents,
  bool quietIfNothingToPrune = false,
}) async {
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

  for (final agent in agentsToProcess) {
    final pkgs = manifest.sourceUrisForAgent(agent.cliName);
    final pkgsToPrune = pkgs.keys
        .where(
          (uri) =>
              uri.startsWith('package:') &&
              !referencedNames.contains(uri.substring('package:'.length)),
        )
        .toSet();
    prunedPackages.addAll(pkgsToPrune);
    if (pkgsToPrune.isEmpty) continue;

    final result = await installer.removeSkillsForIde(
      agent: agent,
      rootPath: rootPath,
      manifest: manifest,
      sourceUris: pkgsToPrune,
    );
    manifest = result.manifest;
    totalRemoved += result.removedCount;
    for (final info in result.removed) {
      logger.info('  [${info.agentName}] Removed ${info.skillName}');
    }
  }

  var totalGitSourcesRemoved = 0;

  // Prompt to remove local git sources in manifest with no skills listed.
  if (dialogSupport != null) {
    final askedLocalUris = <String, bool>{};
    for (final agent in agentsToProcess) {
      final sourceEntries = manifest.sourceUrisForAgent(agent.cliName);
      for (final MapEntry(key: uri, value: entry) in sourceEntries.entries) {
        if (uri.startsWith('package:') || entry.skills.isNotEmpty) continue;

        final shouldRemove =
            askedLocalUris[uri] ??
            await (() async {
              final selection = await dialogSupport.showSingleSelectDialog(
                const ['Yes', 'No'],
                title:
                    'Remove local git source "$uri" which has no skills '
                    'installed?',
              );
              final remove = selection == 0;
              askedLocalUris[uri] = remove;
              return remove;
            })();

        if (shouldRemove) {
          manifest = manifest.withoutSourceUri(agent.cliName, uri);
          totalGitSourcesRemoved++;
          logger.info('Removed local git source "$uri".');
        }
      }
    }
  }

  // Prompt to remove global git sources with no skills installed.
  if (dialogSupport != null && globalConfig.gitRepos.isNotEmpty) {
    var updatedRepos = globalConfig.gitRepos;
    for (final repo in globalConfig.gitRepos) {
      final active = await _hasActiveInstalls(repo: repo, manifest: manifest);
      if (active) continue;

      final selection = await dialogSupport.showSingleSelectDialog(
        const ['Yes', 'No'],
        title:
            'Remove global git source "${repo.cloneUrl}" which has no '
            'skills installed?',
      );
      if (selection == 0) {
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
