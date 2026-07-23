// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io' as io;

import 'package:io/ansi.dart' as ansi;

import 'package:args/command_runner.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:skills/src/commands/skills_command.dart';
import 'package:skills/src/core/advisory_checker.dart';
import 'package:skills/src/core/git_runner.dart';
import 'package:skills/src/core/package_resolver.dart';
import 'package:skills/src/core/pub_runner.dart';
import 'package:skills/src/core/git_scanner.dart';
import 'package:skills/src/core/git_sync.dart';
import 'package:skills/src/core/git_repos.dart';
import 'package:skills/src/core/skill_installer.dart';
import 'package:skills/src/core/skill_scanner.dart';
import 'package:skills/src/core/workspace_resolver.dart';
import 'package:skills/src/agent/agent.dart';
import 'package:skills/src/core/dialog_support.dart';
import 'package:skills/src/agent/agent_adapter_factory.dart';
import 'package:skills/src/models/global_config.dart';

import '../models/skill_manifest.dart';
import '../agent/agent_adapter.dart';

/// Installs skills from package dependencies and git repos for [agents].
///
/// If [sourceUris] or [skillNames] are provided and non-empty then only
/// skills from those sources/repos or matching those names will be installed.
/// For packages, entries in [sourceUris] should look like `package:<name>`,
/// and otherwise they should be git URIs which are compatible with the `git`
/// CLI tool.
///
/// Returns `true` on success or `false` otherwise.
Future<bool> getSkills({
  required List<Agent> agents,
  required Logger logger,
  required WorkspaceLayout workspace,
  DialogSupport? dialogSupport,
  GitRunner gitRunner = const GitRunner(),
  String usage = '',
  Set<String> sourceUris = const {},
  Set<String> skillNames = const {},
  bool allFlag = false,
}) async {
  final ready = await PubRunner.ensureWorkspaceConfigs(workspace);
  if (!ready) {
    throw UsageException('Failed to run pub get.', usage);
  }

  // Separate out the package: URIs from git URIs and extract the package
  // name from package URIs.
  final requestedPackages = <String>{};
  final requestedGitUris = <String>{};
  for (var uri in sourceUris) {
    if (uri.startsWith('package:')) {
      requestedPackages.add(uri.substring('package:'.length));
    } else {
      requestedGitUris.add(uri);
    }
  }

  // If git urls were given, but no packages, don't update any packages.
  final packages = sourceUris.isNotEmpty && requestedPackages.isEmpty
      ? const <ResolvedPackage>[]
      : await PackageResolver.resolveWorkspace(
          workspace,
          packageNames: requestedPackages,
        );

  if (requestedPackages.isNotEmpty) {
    if (packages.isEmpty) {
      logger.severe(
        'None of the requested packages were found in dependencies.',
      );
      return false;
    }

    final foundNames = packages.map((p) => p.name).toSet();
    final missing = requestedPackages.difference(foundNames);
    if (missing.isNotEmpty) {
      logger.warning(
        'Warning: The following requested packages were not found in '
        'dependencies: ${missing.join(', ')}',
      );
    }
  }

  final rootPath = workspace.rootPath;
  var manifest = await SkillManifest.loadOrEmptyFromRoot(rootPath);

  final globalConfigPath = GlobalConfig.globalPath;
  final globalConfigFile = io.File(globalConfigPath);
  var globalConfig = await GlobalConfig.loadOrEmpty(globalConfigFile);

  {
    var (originalGlobalConfig, originalManifest) = (globalConfig, manifest);
    (:globalConfig, :manifest) = await _maybePromptToInstallDashSkills(
      dialogSupport: dialogSupport,
      globalConfig: globalConfig,
      agents: agents,
      manifest: manifest,
      resolvedPackages: packages,
      sourceUris: sourceUris,
      skillNames: skillNames,
    );
    // Save any decisions from the prompt
    if (globalConfig != originalGlobalConfig) {
      await globalConfig.save(globalConfigFile);
    }
    if (manifest != originalManifest) {
      await manifest.save(manifestFile(rootPath));
    }
  }

  // If packages were given, but no git repos, don't sync any git repos.
  final _GitData gitData = sourceUris.isNotEmpty && requestedGitUris.isEmpty
      ? const (gitRepoCommits: {}, gitSkills: [])
      : await _syncAndScanGitRepos(
          gitRunner: gitRunner,
          gitUris: requestedGitUris,
          globalConfig: globalConfig,
          manifest: manifest,
          rootPath: rootPath,
          logger: logger,
        );

  await _checkSecurityAdvisories(
    packages: packages,
    rootPath: rootPath,
    logger: logger,
    gitRepoCommits: gitData.gitRepoCommits,
  );

  final scanner = SkillScanner(logger);
  final dartSkills = await scanner.scan(packages);

  final skills = [...dartSkills, ...gitData.gitSkills];

  Map<Agent, Set<String>>? selectedSkillNamesByIde;

  // Log about any unrecognized skills
  if (skillNames.isNotEmpty) {
    final foundSkillNames = skills.map((s) => s.skillName).toSet();
    final missingSkills = skillNames.difference(foundSkillNames);
    if (missingSkills.isNotEmpty) {
      logger.warning(
        'Warning: The following requested skills were not found: '
        '${missingSkills.join(', ')}',
      );
    }
  }

  final agentAdapters = [
    for (final agent in agents)
      createAgentAdapter(agent, rootPath, dialogSupport),
  ];

  final skillsBySource = _groupSkillsBySourceAndFindRemoved(
    skills: skills,
    agentAdapters: agentAdapters,
    manifest: manifest,
    sourceUris: sourceUris,
  );

  if (skillsBySource.isEmpty) {
    final plural = sourceUris.length > 1 ? 's' : '';
    final filterDescription = sourceUris.isNotEmpty
        ? ' in the given source$plural ${sourceUris.join(', ')}'
        : '';
    logger.info('No skills found$filterDescription.');
    return false;
  }

  final sortedSourceIds = skillsBySource.keys.toList()..sort();

  final skillStatesResult = await _computeSkillStates(
    sortedSourceIds: sortedSourceIds,
    skillsBySource: skillsBySource,
    agentAdapters: agentAdapters,
    manifest: manifest,
  );

  final allSkillStates = skillStatesResult.allSkillStates;
  final sourceIdsWithDiff = skillStatesResult.sourceIdsWithDiff;

  if (!allFlag &&
      dialogSupport != null &&
      sourceUris.isEmpty &&
      skillNames.isEmpty) {
    final continueInstall = await _promptForSourcesWithDiffs(
      sourceIdsWithDiff: sourceIdsWithDiff,
      skillsBySource: skillsBySource,
      sortedSourceIds: sortedSourceIds,
      skills: skills,
      dialogSupport: dialogSupport,
      logger: logger,
    );
    if (!continueInstall) {
      return false;
    }
  }

  // Use `skillNames` or the `--all` flag as the selection if provided,
  // otherwise prompt for which skills to install or log the available skills.
  if (skillNames.isNotEmpty) {
    selectedSkillNamesByIde = {};
    for (final agent in agents) {
      selectedSkillNamesByIde[agent] = skillNames;
    }
  } else if (!allFlag) {
    final promptResult = await _promptForSkillsToInstall(
      sortedSourceIds: sortedSourceIds,
      skillsBySource: skillsBySource,
      sourceIdsWithDiff: sourceIdsWithDiff,
      allSkillStates: allSkillStates,
      agentAdapters: agentAdapters,
      agents: agents,
      dialogSupport: dialogSupport,
      logger: logger,
    );
    if (!promptResult.continueInstall) {
      return false;
    }
    selectedSkillNamesByIde = promptResult.selectedSkillNamesByIde;
  }

  final installer = SkillInstaller(dialogSupport);
  for (final agent in agents) {
    final result = await installer.installSkillsForIde(
      agent: agent,
      rootPath: rootPath,
      skills: skills,
      selectedSkills: selectedSkillNamesByIde?[agent],
      previousManifest: manifest,
      globalConfig: globalConfig,
      sourceUris: sourceUris, // this still acts as source filter
    );
    if (result == null) {
      logger.warning('Installation aborted for agent ${agent.cliName}');
      continue;
    }
    manifest = result.manifest;
    globalConfig = result.globalConfig;
    for (final info in result.installed) {
      logger.info('  [${info.agentName}] Installed ${info.skillName}');
    }
    logger.info(
      'Installed ${result.installed.length} skill(s) for ${agent.cliName}.',
    );
  }

  await globalConfig.save(globalConfigFile);
  await manifest.save(manifestFile(rootPath));

  return true;
}

typedef DashSkillsPromptResult = ({
  GlobalConfig globalConfig,
  SkillManifest manifest,
});

/// Prompts the user to install dash skill repos if they have not already
/// been prompted for this package, haven't globally opted out of these prompts,
/// and [dialogSupport] exists.
Future<DashSkillsPromptResult> _maybePromptToInstallDashSkills({
  required DialogSupport? dialogSupport,
  required GlobalConfig globalConfig,
  required List<Agent> agents,
  required SkillManifest manifest,
  required List<ResolvedPackage> resolvedPackages,
  required Set<String> sourceUris,
  required Set<String> skillNames,
}) async {
  // Only prompt when we can have dialog support, and the user didn't already
  // specify specific skills or sources.
  if (globalConfig.neverPromptForSuggestedSkills ||
      dialogSupport == null ||
      sourceUris.isNotEmpty ||
      skillNames.isNotEmpty) {
    return (globalConfig: globalConfig, manifest: manifest);
  }

  const flutterSkillsRepo = 'https://github.com/flutter/agent-plugins.git';
  const dartSkillsRepo = 'https://github.com/dart-lang/skills.git';
  final suggestedRepos = <String>[];
  bool shouldSuggest(String repoUrl) {
    return !manifest.suggestedRepos.contains(repoUrl) &&
        !globalConfig.gitRepos.any((r) => r.cloneUrl == repoUrl) &&
        !manifest.gitRepos.any((r) => r.cloneUrl == repoUrl);
  }

  if (shouldSuggest(dartSkillsRepo)) {
    suggestedRepos.add(dartSkillsRepo);
  }

  final hasFlutter = resolvedPackages.any((p) => p.name == 'flutter');
  if (hasFlutter && shouldSuggest(flutterSkillsRepo)) {
    suggestedRepos.add(flutterSkillsRepo);
  }

  if (suggestedRepos.isNotEmpty) {
    final options = [...suggestedRepos, 'Never ask again on this machine'];
    final selectedIndices = await dialogSupport.showMultiSelectDialog(
      options,
      title: hasFlutter
          ? installDartOrFlutterSkillsText
          : installDartSkillsText,
      initialSelected: {for (var i = 0; i < suggestedRepos.length; i++) i},
    );
    // Record that we prompted regardless of result, even if they skipped it.
    manifest = manifest.withPromptedSuggestedRepos(suggestedRepos.toSet());

    if (selectedIndices != null) {
      final neverAskAgainIndex = options.length - 1;
      if (selectedIndices.contains(neverAskAgainIndex)) {
        globalConfig = globalConfig.withNeverPromptForSuggestedSkills(true);
      }

      final selectedRepos = <String>[];
      for (var i = 0; i < suggestedRepos.length; i++) {
        if (selectedIndices.contains(i)) {
          selectedRepos.add(suggestedRepos[i]);
        }
      }

      if (selectedRepos.isNotEmpty) {
        final result = await dialogSupport.showSingleSelectDialog([
          'Local (this package only)',
          'Global (all packages)',
        ], title: 'Install suggested repos globally or locally?');

        if (result == 0) {
          for (final ide in agents) {
            for (final repo in selectedRepos) {
              manifest = manifest.withSourceUri(
                ide.cliName,
                repo,
                const SkillsEntry(),
              );
            }
          }
        } else if (result == 1) {
          for (final repo in selectedRepos) {
            globalConfig = globalConfig.withGitRepo(GitRepo(cloneUrl: repo));
          }
        }
      }
    }
  }

  return (globalConfig: globalConfig, manifest: manifest);
}

@visibleForTesting
const installDartSkillsText =
    'Would you like to install the official Dart skills?';

@visibleForTesting
const installDartOrFlutterSkillsText =
    'Would you like to install the official Dart or Flutter skills?';

/// Syncs and scans git repos from [globalConfig] and [manifest].
///
/// If git is available, it syncs the repositories, scans for global and local
/// git skills, and records the git commits for each repo.
///
/// If [gitUris] is not empty, only those git repos are synced and checked.
Future<_GitData> _syncAndScanGitRepos({
  required GitRunner gitRunner,
  required GlobalConfig globalConfig,
  required SkillManifest manifest,
  required String rootPath,
  required Logger logger,
  Set<String> gitUris = const {},
}) async {
  final gitSkills = <ScannedSkill>[];
  final gitRepoCommits = <String, String>{};

  if (await gitRunner.isAvailable) {
    final gitSync = GitSync(
      repos: [
        for (var repo in globalConfig.gitRepos.followedBy(manifest.gitRepos))
          if (gitUris.isEmpty || gitUris.contains(repo.cloneUrl)) repo,
      ],
    );
    await gitSync.sync(rootPath, onProgress: logger.info);

    final gitScanner = GitScanner();
    gitSkills
      ..addAll(
        await gitScanner.scan(
          rootPath,
          isGlobal: true,
          repos: [
            for (var repo in globalConfig.gitRepos)
              if (gitUris.isEmpty || gitUris.contains(repo.cloneUrl)) repo,
          ],
        ),
      )
      ..addAll(
        await gitScanner.scan(
          rootPath,
          isGlobal: false,
          repos: [
            for (var repo in manifest.gitRepos)
              if (gitUris.isEmpty || gitUris.contains(repo.cloneUrl)) repo,
          ],
        ),
      );

    for (final repo in gitSync.repos) {
      final repoPath = gitRepoPath(rootPath, repo);
      final commit = await _getGitCommit(repoPath);
      if (commit != null) {
        gitRepoCommits[repo.cloneUrl] = commit;
      }
    }
  } else {
    logger.warning('Warning: git not found. Skipping git repo skills.');
  }

  return (gitSkills: gitSkills, gitRepoCommits: gitRepoCommits);
}

/// Checks for security advisories for the given [packages] using OSV.dev.
///
/// Logs warnings if any known security advisories exist for the given packages
/// or git commits.
Future<void> _checkSecurityAdvisories({
  required List<ResolvedPackage> packages,
  required String rootPath,
  required Logger logger,
  required Map<String, String> gitRepoCommits,
}) async {
  final advisoryChecker = AdvisoryChecker();
  final advisories = await advisoryChecker.checkAdvisories(
    packages,
    rootPath,
    logger,
    gitRepoCommits: gitRepoCommits,
  );
  if (advisories.isNotEmpty) {
    final buffer = StringBuffer()
      ..writeln('Warning: Found security advisories:');
    for (final entry in advisories.entries) {
      buffer.writeln('  ${entry.key}:');
      for (final summary in entry.value) {
        buffer.writeln('    - $summary');
      }
    }
    logger.warning(buffer.toString());
  }
}

/// Groups scanned [skills] by their source URI.
///
/// It also compares the scanned skills against the previously installed skills
/// from the [manifest] to identify any skills that were removed or are no
/// longer present in the dependencies, returning them as [OrphanedSkill]
/// instances.
///
/// If [sourceUris] is non-empty, then only skills from those sources are
/// returned.
Map<String, List<ScannedSkill>> _groupSkillsBySourceAndFindRemoved({
  required List<ScannedSkill> skills,
  required List<AgentAdapter> agentAdapters,
  required SkillManifest manifest,
  required Set<String> sourceUris,
}) {
  final skillsBySource = <String, List<ScannedSkill>>{};
  for (final skill in skills) {
    final sourceId = skill.sourceUri;
    skillsBySource.putIfAbsent(sourceId, () => []).add(skill);
  }

  for (final adapter in agentAdapters) {
    final existingPkgs = manifest.sourceUrisForAgent(adapter.agent.cliName);
    for (final MapEntry(key: sourceUri, value: entry) in existingPkgs.entries) {
      if (sourceUris.isNotEmpty && !sourceUris.contains(sourceUri)) continue;

      for (final existingSkill in entry.skills) {
        if (!existingSkill.isInstalled) continue;

        final isStillPresent = skills.any(
          (s) => s.sourceUri == sourceUri && s.skillName == existingSkill.name,
        );
        if (!isStillPresent) {
          final orphanedSkill = OrphanedSkill(
            sourceUri: sourceUri,
            skillName: existingSkill.name,
          );
          final sourceId = orphanedSkill.sourceUri;
          final list = skillsBySource.putIfAbsent(sourceId, () => []);
          if (list.where((s) => s.skillName == existingSkill.name).isEmpty) {
            list.add(orphanedSkill);
          }
        }
      }
    }
  }

  return skillsBySource;
}

/// Computes the installation state for all scanned [skillsBySource].
///
/// For each skill and each agent adapter, determines whether the skill is new,
/// up-to-date, has local edits, has an update available, or was removed.
Future<_SkillStatesResult> _computeSkillStates({
  required List<String> sortedSourceIds,
  required Map<String, List<ScannedSkill>> skillsBySource,
  required List<AgentAdapter> agentAdapters,
  required SkillManifest manifest,
}) async {
  final allSkillStates = <ScannedSkill, Map<AgentAdapter, _SkillState>>{};
  final sourceIdsWithDiff = <String>{};

  for (final sourceId in sortedSourceIds) {
    final sourceSkills = skillsBySource[sourceId]!;
    sourceSkills.sort((a, b) => a.skillName.compareTo(b.skillName));

    for (final skill in sourceSkills) {
      final statesForSkill = allSkillStates[skill] =
          <AgentAdapter, _SkillState>{};

      for (final adapter in agentAdapters) {
        final newHash = switch (skill.skillPath) {
          null => null,
          String path => await adapter.computeSourceSkillHash(
            io.Directory(path),
          ),
        };
        var state = _SkillState.isNew;
        final currentSkillEntry = manifest
            .sourceUrisForAgent(adapter.agent.cliName)[skill.sourceUri]
            ?.skills
            .where((s) => s.name == skill.skillName)
            .firstOrNull;

        if (currentSkillEntry != null) {
          if (!currentSkillEntry.isInstalled) {
            state = _SkillState.skipped;
          } else if (skill is OrphanedSkill) {
            state = _SkillState.removed;
          } else {
            final currentHash = await adapter.computeInstalledSkillHash(
              skill.skillName,
            );
            final installedHash = currentSkillEntry.contentHash;
            if (installedHash != null && currentHash != installedHash) {
              state = _SkillState.localEdits;
            } else if (newHash != installedHash) {
              state = _SkillState.updateAvailable;
            } else {
              state = _SkillState.upToDate;
            }
          }
        }
        statesForSkill[adapter] = state;
        if (state != _SkillState.upToDate) {
          sourceIdsWithDiff.add(sourceId);
        }
      }
    }
  }

  return (allSkillStates: allSkillStates, sourceIdsWithDiff: sourceIdsWithDiff);
}

/// Prompts the user to filter skills by the sources they come from.
///
/// If there are skills with differences across multiple sources, a dialog is
/// shown for the user to select which sources to include. Unselected sources
/// and their skills are removed from the input sets.
///
/// Returns `true` if the installation should continue, or `false` if aborted.
Future<bool> _promptForSourcesWithDiffs({
  required Set<String> sourceIdsWithDiff,
  required Map<String, List<ScannedSkill>> skillsBySource,
  required List<String> sortedSourceIds,
  required List<ScannedSkill> skills,
  required DialogSupport dialogSupport,
  required Logger logger,
}) async {
  final sourcesWithSkills = sourceIdsWithDiff.toList()..sort();
  if (sourcesWithSkills.isNotEmpty) {
    final initialSelected = Iterable<int>.generate(
      sourcesWithSkills.length,
    ).toSet();
    final selectedIndices = await dialogSupport.showMultiSelectDialog(
      sourcesWithSkills,
      title: 'Select sources to install skills from:',
      initialSelected: initialSelected,
    );
    if (selectedIndices != null) {
      final selectedSources = selectedIndices
          .map((i) => sourcesWithSkills[i])
          .toSet();
      skills.removeWhere(
        (s) =>
            sourceIdsWithDiff.contains(s.sourceUri) &&
            !selectedSources.contains(s.sourceUri),
      );

      for (final list in skillsBySource.values) {
        list.removeWhere(
          (s) =>
              sourceIdsWithDiff.contains(s.sourceUri) &&
              !selectedSources.contains(s.sourceUri),
        );
      }
      skillsBySource.removeWhere((k, v) => v.isEmpty);
      sortedSourceIds.removeWhere((id) => !skillsBySource.containsKey(id));
      sourceIdsWithDiff.removeWhere((id) => !skillsBySource.containsKey(id));
    } else {
      logger.info('Installation aborted by user.');
      return false; // aborted
    }
  }
  return true; // continue
}

/// Prompts the user to select which specific skills to install, update, or remove.
///
/// Displays an interactive dialog (or logs if [dialogSupport] is null) with the
/// computed states (e.g. New, Update available, Local edits) for each skill.
///
/// Returns a continue boolean and a map of selected skill names by agent.
Future<_PromptResult> _promptForSkillsToInstall({
  required List<String> sortedSourceIds,
  required Map<String, List<ScannedSkill>> skillsBySource,
  required Set<String> sourceIdsWithDiff,
  required Map<ScannedSkill, Map<AgentAdapter, _SkillState>> allSkillStates,
  required List<AgentAdapter> agentAdapters,
  required List<Agent> agents,
  required DialogSupport? dialogSupport,
  required Logger logger,
}) async {
  final selectedSkillNamesByIde = <Agent, Set<String>>{
    for (final agent in agents) agent: {},
  };
  var hasAnyChangesToPrint = false;

  for (final sourceId in sortedSourceIds) {
    final sourceSkills = skillsBySource[sourceId]!;

    if (!sourceIdsWithDiff.contains(sourceId)) {
      continue;
    }

    hasAnyChangesToPrint = true;
    final options = <String>[];
    final initialSelected = <int>{};
    final dialogOptions = <_DialogOption>[];

    for (final skill in sourceSkills) {
      final statesForSkill = allSkillStates[skill]!;
      final adaptersByState = <_SkillState, List<AgentAdapter>>{};
      for (final entry in statesForSkill.entries) {
        adaptersByState.putIfAbsent(entry.value, () => []).add(entry.key);
      }

      for (final MapEntry(key: state, value: adapters)
          in adaptersByState.entries) {
        if (state == _SkillState.upToDate) {
          continue;
        }

        final labelSuffix = state.label;
        final isSelected = state.selectedDefault;
        final agentstr = adapters.length == agentAdapters.length
            ? ''
            : ' for ${adapters.map((a) => a.agent.cliName).join(', ')}';

        final formattedSkillName = formatSkillName(
          skill.skillName,
          packageName: skill.packageName,
        );
        final fullLabel = '$formattedSkillName$agentstr ($labelSuffix)';

        dialogOptions.add((
          skill: skill,
          adapters: adapters,
          state: state,
          label: state.colorize(fullLabel),
          isSelected: isSelected,
        ));
      }
    }

    dialogOptions.sort((a, b) {
      if (a.state.index != b.state.index) {
        return a.state.index.compareTo(b.state.index);
      }
      return a.skill.skillName.compareTo(b.skill.skillName);
    });

    for (var i = 0; i < dialogOptions.length; i++) {
      options.add(dialogOptions[i].label);
      if (dialogOptions[i].isSelected) {
        initialSelected.add(i);
      }
    }

    final displayName = sourceId;

    if (dialogSupport == null) {
      logger.info('Available skills from $displayName:');
      for (final opt in dialogOptions) {
        logger.info('  ${opt.label}');
      }
    } else {
      final selectedIndices = await dialogSupport.showMultiSelectDialog(
        options,
        title: 'Select skills to install/update from $displayName:',
        initialSelected: initialSelected,
      );

      if (selectedIndices != null) {
        for (final index in selectedIndices) {
          final opt = dialogOptions[index];
          for (final adapter in opt.adapters) {
            selectedSkillNamesByIde[adapter.agent]!.add(opt.skill.skillName);
          }
        }
      } else {
        logger.info('Installation aborted by user.');
        return (continueInstall: false, selectedSkillNamesByIde: null);
      }
    }
  }

  if (!hasAnyChangesToPrint) {
    logger.info('All skills are up to date.');
    return (continueInstall: false, selectedSkillNamesByIde: null);
  }

  if (dialogSupport == null) {
    logger.info(
      'Rerun with `--skill <name>`, or `--all` to '
      'install, update, or remove the given skills.',
    );
    return (continueInstall: false, selectedSkillNamesByIde: null);
  }

  return (
    continueInstall: true,
    selectedSkillNamesByIde: selectedSkillNamesByIde,
  );
}

Future<String?> _getGitCommit(String repoPath) async {
  try {
    final result = await io.Process.run(
      'git',
      ['rev-parse', 'HEAD'],
      workingDirectory: repoPath,
      runInShell: true,
    );
    if (result.exitCode == 0) {
      return (result.stdout as String).trim();
    }
  } catch (e) {
    // Ignore
  }
  return null;
}

enum _SkillState {
  localEdits('Local edits', false),
  isNew('New', false),
  updateAvailable('Update available', true),
  removed('Removed', true),
  skipped('Skipped previously', false),
  upToDate('', false);

  final String label;
  final bool selectedDefault;

  const _SkillState(this.label, this.selectedDefault);

  String colorize(String text) {
    return switch (this) {
          _SkillState.localEdits => ansi.yellow.wrap(text),
          _SkillState.isNew => ansi.cyan.wrap(text),
          _SkillState.updateAvailable => ansi.green.wrap(text),
          _SkillState.removed => ansi.red.wrap(text),
          _SkillState.skipped => ansi.darkGray.wrap(text),
          _SkillState.upToDate => ansi.green.wrap(text),
        } ??
        text;
  }
}

typedef _GitData = ({
  List<ScannedSkill> gitSkills,
  Map<String, String> gitRepoCommits,
});

typedef _SkillStatesResult = ({
  Map<ScannedSkill, Map<AgentAdapter, _SkillState>> allSkillStates,
  Set<String> sourceIdsWithDiff,
});

typedef _PromptResult = ({
  bool continueInstall,
  Map<Agent, Set<String>>? selectedSkillNamesByIde,
});

typedef _DialogOption = ({
  ScannedSkill skill,
  List<AgentAdapter> adapters,
  _SkillState state,
  String label,
  bool isSelected,
});

/// An orphaned skill is one that was deleted upstream.
///
/// These can exist during the upgrade process, and the user chooses whether
/// to uninstall them or keep them. If they keep them, then they are no longer
/// tracked by the manifest and the user must manage them on their own after
/// that.
class OrphanedSkill implements ScannedSkill {
  @override
  bool get isGlobal => false;

  @override
  final String? packageName;

  @override
  final String? gitUrl;

  @override
  final String skillName;

  /// Not a real skill, has no path
  @override
  String? get skillPath => null;

  @override
  String get sourceUri => gitUrl ?? 'package:${packageName!}';

  OrphanedSkill({required String sourceUri, required this.skillName})
    : packageName = sourceUri.startsWith('package:')
          ? sourceUri.substring(8)
          : null,
      gitUrl = sourceUri.startsWith('package:') ? null : sourceUri {
    if (gitUrl == null && packageName == null) {
      throw StateError('One of $gitUrl or $packageName must be non-null');
    }
  }
}
