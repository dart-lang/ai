import 'dart:io' as io;

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
import 'package:skills/src/models/global_config.dart';

import '../models/skill_manifest.dart';

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
      logger
          .severe('None of the requested packages were found in dependencies.');
      return false;
    }

    final foundNames = packages.map((p) => p.name).toSet();
    final missing = packageNames.difference(foundNames);
    if (missing.isNotEmpty) {
      logger.warning(
          'Warning: The following requested packages were not found in '
          'dependencies: ${missing.join(', ')}');
    }
  }

  final rootPath = workspace.rootPath;
  var manifest = await SkillManifest.loadOrEmptyFromRoot(rootPath);

  final globalConfigPath = GlobalConfig.globalPath;
  final globalConfigFile = io.File(globalConfigPath);
  var globalConfig = await GlobalConfig.loadOrEmpty(globalConfigFile);

  final registrySkills = <ScannedSkill>[];
  final registryRepoCommits = <String, String>{};

  if (await gitRunner.isAvailable) {
    final registrySync = RegistrySync(
        repos: [...globalConfig.registries, ...manifest.registries]);
    await registrySync.sync(rootPath, onProgress: logger.info);

    final registryScanner = RegistryScanner();
    registrySkills
      ..addAll(await registryScanner.scan(
        rootPath,
        isGlobal: true,
        repos: globalConfig.registries,
      ))
      ..addAll(await registryScanner.scan(
        rootPath,
        isGlobal: false,
        repos: manifest.registries,
      ));

    for (final repo in registrySync.repos) {
      final repoPath = registryRepoPath(rootPath, repo);
      final commit = await _getGitCommit(repoPath);
      if (commit != null) {
        registryRepoCommits[repo.cloneUrl] = commit;
      }
    }
  } else {
    logger.warning(
      'Warning: git not found. Skipping GitHub registry skills.',
    );
  }

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

  final scanner = SkillScanner(logger);
  final dartSkills = await scanner.scan(packages);

  final resolvedPackageNames = packages.map((p) => p.name).toSet();
  var skills = mergeSkills(
    dartSkills: dartSkills,
    registrySkills: registrySkills,
    resolvedPackageNames: resolvedPackageNames,
  );

  if (skills.isEmpty) {
    final plural = resolvedPackageNames.length > 1 ? 's' : '';
    final filterDescription = resolvedPackageNames.isNotEmpty
        ? ' in the given package$plural ${resolvedPackageNames.join(', ')}'
        : '';
    logger.info('No skills found$filterDescription.');
    return false;
  }

  if (skillNames.isNotEmpty) {
    final foundSkillNames = skills.map((s) => s.skillName).toSet();
    final missingSkills = skillNames.difference(foundSkillNames);
    if (missingSkills.isNotEmpty) {
      logger.warning('Warning: The following requested skills were not found: '
          '${missingSkills.join(', ')}');
    }
    skills.removeWhere((s) => !skillNames.contains(s.skillName));
  } else if (!allFlag) {
    if (dialogSupport == null) {
      // Just print the available skills if no dialog support and the user did not
      // specify --all or --skill.
      logger.info('Available skills:');
      final sortedSkills = List<ScannedSkill>.from(skills)
        ..sort((a, b) => a.skillName.compareTo(b.skillName));
      for (final skill in sortedSkills) {
        logger.info(
            '  ${skill.skillName} (from ${_getSourceDisplayName(skill)})');
      }
      logger.info('Rerun with `--skill <name>`, or `--all` to '
          'install the chosen skills.');
      return false;
    } else {
      // We have dialog support, have the user select the packages to install
      // skills for and then the specific skills.
      if (packageNames.isEmpty) {
        final packagesWithSkills =
            skills.map((skill) => skill.packageName).toSet().toList()..sort();
        if (packagesWithSkills.isNotEmpty) {
          final initialSelected =
              Iterable<int>.generate(packagesWithSkills.length).toSet();
          final selectedIndices = await dialogSupport.showMultiSelectDialog(
            packagesWithSkills,
            title: 'Select packages to install skills from:',
            initialSelected: initialSelected,
          );
          if (selectedIndices != null) {
            final selectedPackages =
                selectedIndices.map((i) => packagesWithSkills[i]).toSet();
            skills
                .removeWhere((s) => !selectedPackages.contains(s.packageName));
          } else {
            logger.info('Installation aborted by user.');
            return false;
          }
        }
      }

      if (skills.isNotEmpty) {
        final skillsBySource = <String, List<ScannedSkill>>{};
        for (final skill in skills) {
          final sourceId = _getSourceId(skill);
          skillsBySource.putIfAbsent(sourceId, () => []).add(skill);
        }

        final sortedSourceIds = skillsBySource.keys.toList()
          ..sort((a, b) {
            final skillA = skillsBySource[a]!.first;
            final skillB = skillsBySource[b]!.first;
            return _getSourceDisplayName(skillA)
                .compareTo(_getSourceDisplayName(skillB));
          });

        for (final sourceId in sortedSourceIds) {
          final sourceSkills = skillsBySource[sourceId]!;
          if (sourceSkills.length > 1) {
            sourceSkills.sort((a, b) => a.skillName.compareTo(b.skillName));
            final skillNamesList =
                sourceSkills.map((s) => s.skillName).toList();
            final initialSelected =
                Iterable<int>.generate(sourceSkills.length).toSet();

            final displayName = _getSourceDisplayName(sourceSkills.first);
            final selectedIndices = await dialogSupport.showMultiSelectDialog(
              skillNamesList,
              title: 'Select skills to install from $displayName:',
              initialSelected: initialSelected,
            );

            if (selectedIndices != null) {
              final selectedSkills =
                  selectedIndices.map((i) => sourceSkills[i]).toSet();
              skills.removeWhere((s) =>
                  _getSourceId(s) == sourceId && !selectedSkills.contains(s));
            } else {
              logger.info('Installation aborted by user.');
              return false;
            }
          }
        }
      }
    }
  }

  if (skills.isEmpty) {
    logger.info('No skills selected to install.');
    return false;
  }

  final installer = SkillInstaller(dialogSupport);

  for (final ide in ides) {
    final result = await installer.installSkillsForIde(
      ide: ide,
      rootPath: rootPath,
      skills: skills,
      manifest: manifest,
      globalConfig: globalConfig,
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
  }

  await globalConfig.save(globalConfigFile);
  await manifest.save(manifestFile(rootPath));

  final ideNames = ides.map((e) => e.cliName).join(', ');
  logger.info('Installed ${skills.length} skill(s) for $ideNames.');

  return true;
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
