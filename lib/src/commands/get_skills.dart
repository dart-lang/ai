import 'dart:io' as io;

import 'package:io/ansi.dart' as ansi;

import 'package:args/command_runner.dart';
import 'package:logging/logging.dart';
import 'package:skills/src/commands/skills_command.dart';
import 'package:skills/src/core/advisory_checker.dart';
import 'package:skills/src/core/git_runner.dart';
import 'package:skills/src/core/package_resolver.dart';
import 'package:skills/src/core/pub_runner.dart';
import 'package:skills/src/core/registry_scanner.dart';
import 'package:skills/src/core/registry_sync.dart';
import 'package:skills/src/core/registry_repos.dart';
import 'package:skills/src/core/skill_installer.dart';
import 'package:skills/src/core/skill_merger.dart';
import 'package:skills/src/core/skill_scanner.dart';
import 'package:skills/src/core/workspace_resolver.dart';
import 'package:skills/src/ide/ide.dart';
import 'package:skills/src/core/dialog_support.dart';
import 'package:skills/src/ide/ide_adapter_factory.dart';
import 'package:skills/src/models/global_config.dart';

import '../models/skill_manifest.dart';
import '../ide/ide_adapter.dart';

/// Installs skills from package dependencies for [ides].
///
/// If [packageNames] or [skillNames] are provided and non-empty then only
/// skills from those packages or matching those names will be installed.
///
/// Returns `true` on success or `false` otherwise.
Future<bool> getSkills({
  required List<Ide> ides,
  required Logger logger,
  required WorkspaceLayout workspace,
  DialogSupport? dialogSupport,
  GitRunner gitRunner = const GitRunner(),
  String usage = '',
  Set<String> packageNames = const {},
  Set<String> skillNames = const {},
  bool allFlag = false,
}) async {
  final ready = await PubRunner.ensureWorkspaceConfigs(workspace);
  if (!ready) {
    throw UsageException('Failed to run pub get.', usage);
  }

  final packages = await PackageResolver.resolveWorkspace(
    workspace,
    packageNames: packageNames,
  );

  if (packageNames.isNotEmpty) {
    if (packages.isEmpty) {
      logger.severe(
        'None of the requested packages were found in dependencies.',
      );
      return false;
    }

    final foundNames = packages.map((p) => p.name).toSet();
    final missing = packageNames.difference(foundNames);
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

  final registryData = await _syncAndScanRegistries(
    gitRunner: gitRunner,
    globalConfig: globalConfig,
    manifest: manifest,
    rootPath: rootPath,
    logger: logger,
  );

  await _checkSecurityAdvisories(
    packages: packages,
    rootPath: rootPath,
    logger: logger,
    registryRepoCommits: registryData.registryRepoCommits,
  );

  final scanner = SkillScanner(logger);
  final dartSkills = await scanner.scan(packages);

  final resolvedPackageNames = packages.map((p) => p.name).toSet();
  var skills = mergeSkills(
    dartSkills: dartSkills,
    registrySkills: registryData.registrySkills,
    resolvedPackageNames: resolvedPackageNames,
  );

  Map<Ide, Set<String>>? selectedSkillNamesByIde;

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

  final ideAdapters = [
    for (final ide in ides) createIdeAdapter(ide, rootPath, dialogSupport),
  ];

  final skillsBySource = _groupSkillsBySourceAndFindRemoved(
    skills: skills,
    ideAdapters: ideAdapters,
    manifest: manifest,
    packageNames: packageNames,
  );

  if (skillsBySource.isEmpty) {
    final plural = resolvedPackageNames.length > 1 ? 's' : '';
    final filterDescription = resolvedPackageNames.isNotEmpty
        ? ' in the given package$plural ${resolvedPackageNames.join(', ')}'
        : '';
    logger.info('No skills found$filterDescription.');
    return false;
  }

  final sortedSourceIds = skillsBySource.keys.toList()..sort();

  final skillStatesResult = await _computeSkillStates(
    sortedSourceIds: sortedSourceIds,
    skillsBySource: skillsBySource,
    ideAdapters: ideAdapters,
    manifest: manifest,
  );

  final allSkillStates = skillStatesResult.allSkillStates;
  final sourceIdsWithDiff = skillStatesResult.sourceIdsWithDiff;

  if (!allFlag &&
      dialogSupport != null &&
      packageNames.isEmpty &&
      skillNames.isEmpty) {
    final continueInstall = await _promptForPackagesWithDiffs(
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
    for (final ide in ides) {
      selectedSkillNamesByIde[ide] = skillNames;
    }
  } else if (!allFlag) {
    final promptResult = await _promptForSkillsToInstall(
      sortedSourceIds: sortedSourceIds,
      skillsBySource: skillsBySource,
      sourceIdsWithDiff: sourceIdsWithDiff,
      allSkillStates: allSkillStates,
      ideAdapters: ideAdapters,
      ides: ides,
      dialogSupport: dialogSupport,
      logger: logger,
    );
    if (!promptResult.continueInstall) {
      return false;
    }
    selectedSkillNamesByIde = promptResult.selectedSkillNamesByIde;
  }

  final installer = SkillInstaller(dialogSupport);
  for (final ide in ides) {
    final result = await installer.installSkillsForIde(
      ide: ide,
      rootPath: rootPath,
      skills: skills,
      selectedSkills: selectedSkillNamesByIde?[ide],
      previousManifest: manifest,
      globalConfig: globalConfig,
      packageNames: packageNames,
    );
    if (result == null) {
      logger.warning('Installation aborted for IDE ${ide.cliName}');
      continue;
    }
    manifest = result.manifest;
    globalConfig = result.globalConfig;
    for (final info in result.installed) {
      logger.info('  [${info.ideName}] Installed ${info.skillName}');
    }
    logger.info(
      'Installed ${result.installed.length} skill(s) for ${ide.cliName}.',
    );
  }

  await globalConfig.save(globalConfigFile);
  await manifest.save(manifestFile(rootPath));

  return true;
}

/// Syncs and scans skill registries from [globalConfig] and [manifest].
///
/// If git is available, it syncs the repositories, scans for global and local
/// registry skills, and records the git commits for each repo.
Future<_RegistryData> _syncAndScanRegistries({
  required GitRunner gitRunner,
  required GlobalConfig globalConfig,
  required SkillManifest manifest,
  required String rootPath,
  required Logger logger,
}) async {
  final registrySkills = <ScannedSkill>[];
  final registryRepoCommits = <String, String>{};

  if (await gitRunner.isAvailable) {
    final registrySync = RegistrySync(
      repos: [...globalConfig.registries, ...manifest.registries],
    );
    await registrySync.sync(rootPath, onProgress: logger.info);

    final registryScanner = RegistryScanner();
    registrySkills
      ..addAll(
        await registryScanner.scan(
          rootPath,
          isGlobal: true,
          repos: globalConfig.registries,
        ),
      )
      ..addAll(
        await registryScanner.scan(
          rootPath,
          isGlobal: false,
          repos: manifest.registries,
        ),
      );

    for (final repo in registrySync.repos) {
      final repoPath = registryRepoPath(rootPath, repo);
      final commit = await _getGitCommit(repoPath);
      if (commit != null) {
        registryRepoCommits[repo.cloneUrl] = commit;
      }
    }
  } else {
    logger.warning('Warning: git not found. Skipping GitHub registry skills.');
  }

  return (
    registrySkills: registrySkills,
    registryRepoCommits: registryRepoCommits,
  );
}

/// Checks for security advisories for the given [packages] using OSV.dev.
///
/// Logs warnings if any known security advisories exist for the given packages
/// or registry commits.
Future<void> _checkSecurityAdvisories({
  required List<ResolvedPackage> packages,
  required String rootPath,
  required Logger logger,
  required Map<String, String> registryRepoCommits,
}) async {
  final advisoryChecker = AdvisoryChecker();
  final advisories = await advisoryChecker.checkAdvisories(
    packages,
    rootPath,
    logger,
    registryRepoCommits: registryRepoCommits,
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

/// Groups scanned [skills] by their source ID (package or registry URL).
///
/// It also compares the scanned skills against the previously installed skills
/// from the [manifest] to identify any skills that were removed or are no
/// longer present in the dependencies, returning them as `RemovedSkill` instances.
Map<String, List<ScannedSkill>> _groupSkillsBySourceAndFindRemoved({
  required List<ScannedSkill> skills,
  required List<IdeAdapter> ideAdapters,
  required SkillManifest manifest,
  required Set<String> packageNames,
}) {
  final skillsBySource = <String, List<ScannedSkill>>{};
  for (final skill in skills) {
    final sourceId = _getSourceId(skill);
    skillsBySource.putIfAbsent(sourceId, () => []).add(skill);
  }

  for (final adapter in ideAdapters) {
    final existingPkgs = manifest.packagesForIde(adapter.ide.cliName);
    for (final MapEntry(key: pkgName, value: entry) in existingPkgs.entries) {
      if (packageNames.isNotEmpty && !packageNames.contains(pkgName)) {
        continue;
      }
      for (final existingSkill in entry.skills) {
        if (!existingSkill.isInstalled) continue;

        final isStillPresent = skills.any(
          (s) => s.packageName == pkgName && s.skillName == existingSkill.name,
        );
        if (!isStillPresent) {
          final orphanedSkill = OrphanedSkill(
            packageName: pkgName,
            skillName: existingSkill.name,
          );
          final sourceId = _getSourceId(orphanedSkill);
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
/// For each skill and each IDE adapter, determines whether the skill is new,
/// up-to-date, has local edits, has an update available, or was removed.
Future<_SkillStatesResult> _computeSkillStates({
  required List<String> sortedSourceIds,
  required Map<String, List<ScannedSkill>> skillsBySource,
  required List<IdeAdapter> ideAdapters,
  required SkillManifest manifest,
}) async {
  final allSkillStates = <ScannedSkill, Map<IdeAdapter, _SkillState>>{};
  final sourceIdsWithDiff = <String>{};

  for (final sourceId in sortedSourceIds) {
    final sourceSkills = skillsBySource[sourceId]!;
    sourceSkills.sort((a, b) => a.skillName.compareTo(b.skillName));

    for (final skill in sourceSkills) {
      final statesForSkill = allSkillStates[skill] =
          <IdeAdapter, _SkillState>{};

      for (final adapter in ideAdapters) {
        final newHash = switch (skill.skillPath) {
          null => null,
          String path => await adapter.computeSourceSkillHash(
            io.Directory(path),
          ),
        };
        var state = _SkillState.isNew;
        final currentSkillEntry = manifest
            .packagesForIde(adapter.ide.cliName)[skill.packageName]
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

/// Prompts the user to filter skills by the packages they come from.
///
/// If there are skills with differences across multiple packages, a dialog is
/// shown for the user to select which packages to include. Unselected packages
/// and their skills are removed from the input sets.
///
/// Returns `true` if the installation should continue, or `false` if aborted.
Future<bool> _promptForPackagesWithDiffs({
  required Set<String> sourceIdsWithDiff,
  required Map<String, List<ScannedSkill>> skillsBySource,
  required List<String> sortedSourceIds,
  required List<ScannedSkill> skills,
  required DialogSupport dialogSupport,
  required Logger logger,
}) async {
  final packagesWithDiffs = <String>{};
  for (final sourceId in sourceIdsWithDiff) {
    final firstSkill = skillsBySource[sourceId]!.first;
    if (firstSkill.registryUrl == null) {
      packagesWithDiffs.add(firstSkill.packageName);
    }
  }

  final packagesWithSkills = packagesWithDiffs.toList()..sort();
  if (packagesWithSkills.isNotEmpty) {
    final initialSelected = Iterable<int>.generate(
      packagesWithSkills.length,
    ).toSet();
    final selectedIndices = await dialogSupport.showMultiSelectDialog(
      packagesWithSkills,
      title: 'Select packages to install skills from:',
      initialSelected: initialSelected,
    );
    if (selectedIndices != null) {
      final selectedPackages = selectedIndices
          .map((i) => packagesWithSkills[i])
          .toSet();
      skills.removeWhere(
        (s) =>
            packagesWithDiffs.contains(s.packageName) &&
            !selectedPackages.contains(s.packageName),
      );

      for (final list in skillsBySource.values) {
        list.removeWhere(
          (s) =>
              packagesWithDiffs.contains(s.packageName) &&
              !selectedPackages.contains(s.packageName),
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
/// Returns a continue boolean and a map of selected skill names by IDE.
Future<_PromptResult> _promptForSkillsToInstall({
  required List<String> sortedSourceIds,
  required Map<String, List<ScannedSkill>> skillsBySource,
  required Set<String> sourceIdsWithDiff,
  required Map<ScannedSkill, Map<IdeAdapter, _SkillState>> allSkillStates,
  required List<IdeAdapter> ideAdapters,
  required List<Ide> ides,
  required DialogSupport? dialogSupport,
  required Logger logger,
}) async {
  final selectedSkillNamesByIde = <Ide, Set<String>>{
    for (final ide in ides) ide: {},
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
      final adaptersByState = <_SkillState, List<IdeAdapter>>{};
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
        final ideStr = adapters.length == ideAdapters.length
            ? ''
            : ' for ${adapters.map((a) => a.ide.cliName).join(', ')}';

        final fullLabel = '${skill.skillName}$ideStr ($labelSuffix)';

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

    final displayName = _getSourceDisplayName(sourceSkills.first);

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
            selectedSkillNamesByIde[adapter.ide]!.add(opt.skill.skillName);
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

String _getSourceId(ScannedSkill skill) {
  return skill.registryUrl ?? 'pkg:${skill.packageName}';
}

String _getSourceDisplayName(ScannedSkill skill) {
  if (skill.registryUrl != null) {
    return 'registry ${skill.registryUrl!}';
  } else {
    return 'package ${skill.packageName}';
  }
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

typedef _RegistryData = ({
  List<ScannedSkill> registrySkills,
  Map<String, String> registryRepoCommits,
});

typedef _SkillStatesResult = ({
  Map<ScannedSkill, Map<IdeAdapter, _SkillState>> allSkillStates,
  Set<String> sourceIdsWithDiff,
});

typedef _PromptResult = ({
  bool continueInstall,
  Map<Ide, Set<String>>? selectedSkillNamesByIde,
});

typedef _DialogOption = ({
  ScannedSkill skill,
  List<IdeAdapter> adapters,
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
  final String packageName;

  @override
  String? get registryUrl => null;

  @override
  final String skillName;

  /// Not a real skill, has no path
  @override
  String? get skillPath => null;

  OrphanedSkill({required this.packageName, required this.skillName});
}
