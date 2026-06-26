import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../ide/ide.dart';
import '../ide/adapters/agent_skills_adapter.dart';
import '../ide/ide_adapter.dart';
import '../ide/ide_adapter_factory.dart';
import '../models/global_config.dart';
import '../models/skill_manifest.dart';
import 'dialog_support.dart';
import 'skill_scanner.dart';

/// Result of installing skills for an IDE.
class SkillInstallResult {
  /// The updated manifest after installation.
  final SkillManifest manifest;

  /// The updated global config after installation.
  final GlobalConfig globalConfig;

  /// Info for each installed skill (for logging).
  final List<InstalledSkillInfo> installed;

  const SkillInstallResult({
    required this.manifest,
    required this.globalConfig,
    required this.installed,
  });
}

/// Info about a single installed skill.
class InstalledSkillInfo {
  final String ideName;
  final String skillName;
  final String sourceUri;
  final bool isGlobal;

  const InstalledSkillInfo({
    required this.ideName,
    required this.skillName,
    required this.sourceUri,
    this.isGlobal = false,
  });
}

/// Result of removing skills for an IDE.
class SkillRemoveResult {
  /// The updated manifest after removal.
  final SkillManifest manifest;

  /// Number of skills removed.
  final int removedCount;

  /// Info for each removed skill (for logging).
  final List<RemovedSkillInfo> removed;

  const SkillRemoveResult({
    required this.manifest,
    required this.removedCount,
    required this.removed,
  });
}

/// Info about a single removed skill.
class RemovedSkillInfo {
  final String ideName;
  final String skillName;

  const RemovedSkillInfo({required this.ideName, required this.skillName});
}

class _PackageInstallResult {
  final SkillManifest manifest;
  final GlobalConfig globalConfig;
  final List<InstalledSkillEntry> updatedSkillEntries;
  final List<InstalledSkillInfo> installedInfos;

  _PackageInstallResult({
    required this.manifest,
    required this.globalConfig,
    required this.updatedSkillEntries,
    required this.installedInfos,
  });
}

/// Service for installing and removing skills across IDEs.
class SkillInstaller {
  final DialogSupport? _dialogSupport;

  SkillInstaller(this._dialogSupport);

  static final logger = Logger('SkillInstaller');

  /// Installs [skills] for the given [ide] at [rootPath], returning
  /// an updated version of [previousManifest].
  ///
  /// Removes existing skills for each package before reinstalling.
  ///
  /// If [selectedSkills] is provided, only skills with these names will be
  /// modified. This includes deleting of existing skills.
  Future<SkillInstallResult?> installSkillsForIde({
    required Ide ide,
    required String rootPath,
    required List<ScannedSkill> skills,
    required SkillManifest previousManifest,
    required GlobalConfig globalConfig,
    Set<String>? selectedSkills,
    Set<String> sourceUris = const {},
  }) async {
    final adapter = createIdeAdapter(ide, rootPath, _dialogSupport);
    if (adapter is AgentSkillsAdapter) {
      if (!await adapter.performMigrations(previousManifest)) {
        return null;
      }
    }
    await adapter.ensureSkillsDirectory();

    final skillsBySource = _groupSkillsBySource(skills);

    var updatedManifest = previousManifest;
    final installedSkillInfos = <InstalledSkillInfo>[];

    for (final entry in skillsBySource.entries) {
      final sourceUri = entry.key;
      final sourceSkills = entry.value.values;

      final existingPkgs = updatedManifest.sourceUrisForIde(ide.cliName);
      final existingEntry = existingPkgs[sourceUri];

      final skippedSkills = await _uninstallExistingSkills(
        existingEntry: existingEntry,
        selectedSkills: selectedSkills,
        adapter: adapter,
      );

      final result = await _installSkills(
        skills: sourceSkills,
        skippedSkills: skippedSkills,
        selectedSkills: selectedSkills,
        existingEntry: existingEntry,
        ide: ide,
        rootPath: rootPath,
        adapter: adapter,
        globalConfig: globalConfig,
        manifest: updatedManifest,
      );

      updatedManifest = result.manifest;
      globalConfig = result.globalConfig;
      installedSkillInfos.addAll(result.installedInfos);

      _logOrphanedSkills(skippedSkills, adapter, rootPath);

      updatedManifest = updatedManifest.withSourceUri(
        ide.cliName,
        sourceUri,
        SkillsEntry(skills: result.updatedSkillEntries),
      );
    }

    updatedManifest = await _cleanupMissingPackages(
      ide: ide,
      rootPath: rootPath,
      skillsBySource: skillsBySource,
      manifest: updatedManifest,
      selectedSkills: selectedSkills,
      adapter: adapter,
      sourceUris: sourceUris,
    );

    return SkillInstallResult(
      manifest: updatedManifest,
      globalConfig: globalConfig,
      installed: installedSkillInfos,
    );
  }

  /// Converts [skills] to a nested map, keyed by source URI and then skill
  /// name.
  Map<String, Map<String, ScannedSkill>> _groupSkillsBySource(
    List<ScannedSkill> skills,
  ) {
    final skillsBySource = <String, Map<String, ScannedSkill>>{};
    for (final skill in skills) {
      skillsBySource.putIfAbsent(skill.sourceUri, () => {})[skill.skillName] ??=
          skill;
    }
    return skillsBySource;
  }

  /// Uninstalls the [selectedSkills] (or all if not given) in [existingEntry].
  ///
  /// Returns a list of skills in [existingEntry] that were not uninstalled,
  /// either because it failed or they were not in [selectedSkills].
  Future<Set<String>> _uninstallExistingSkills({
    required SkillsEntry? existingEntry,
    required Set<String>? selectedSkills,
    required IdeAdapter adapter,
  }) async {
    final skippedSkills = <String>{};
    if (existingEntry != null) {
      for (final existing in existingEntry.skills) {
        if (selectedSkills != null && !selectedSkills.contains(existing.name)) {
          skippedSkills.add(existing.name);
        } else if (existing.isInstalled &&
            !await adapter.removeSkill(existing.name)) {
          skippedSkills.add(existing.name);
        }
      }
    }
    return skippedSkills;
  }

  /// Logs any remaining [skippedSkills] as orphaned skills.
  void _logOrphanedSkills(
    Set<String> skippedSkills,
    IdeAdapter adapter,
    String rootPath,
  ) {
    if (skippedSkills.isNotEmpty) {
      final buffer = StringBuffer(
        'The following skills were not uninstalled but were deleted '
        'upstream and are now orphaned:\n\n',
      );
      for (final skill in skippedSkills) {
        buffer.writeln(
          '- $skill (installed at ${p.relative(p.join(adapter.skillsDirectory, skill), from: rootPath)})',
        );
      }
      logger.warning(buffer.toString());
    }
  }

  /// Installs [skills], filtered by only the [selectedSkills] if provided.
  ///
  /// If any skill appears in [skippedSkills], those also will not be installed,
  /// because it means they were not properly uninstalled. The [skippedSkills]
  /// set is also modified to remove any skill that is matched.
  ///
  /// The [existingEntry] represents the previous manifest entry for the
  /// package, and any [skippedSkills] entries will just be copied to the new
  /// [_PackageInstallResult.updatedSkillEntries].
  ///
  /// A modified local [manifest] and [globalConfig] are returned as a part of
  /// the [_PackageInstallResult].
  Future<_PackageInstallResult> _installSkills({
    required Iterable<ScannedSkill> skills,
    required Set<String> skippedSkills,
    required Set<String>? selectedSkills,
    required SkillsEntry? existingEntry,
    required Ide ide,
    required String rootPath,
    required IdeAdapter adapter,
    required GlobalConfig globalConfig,
    required SkillManifest manifest,
  }) async {
    final updatedSkillEntries = <InstalledSkillEntry>[];
    final installedInfos = <InstalledSkillInfo>[];
    var updatedGlobalConfig = globalConfig;
    var updatedManifest = manifest;

    for (final skill in skills) {
      // We skipped uninstalling this skill, just copy its old install entry.
      if (skippedSkills.remove(skill.skillName)) {
        final existing = existingEntry!.skills.firstWhere(
          (s) => s.name == skill.skillName,
        );
        updatedSkillEntries.add(existing);
        continue;
      }

      // New skill, but not in the selected skills to install.
      if (selectedSkills != null && !selectedSkills.contains(skill.skillName)) {
        updatedSkillEntries.add(
          InstalledSkillEntry(
            name: skill.skillName,
            installedAt: DateTime.now().toUtc(),
            contentHash: null,
            isInstalled: false,
          ),
        );
        continue;
      }

      // Actually install the new skill
      final installResult = await adapter.installSkill(skill);
      final installedName = installResult.name;
      updatedSkillEntries.add(
        InstalledSkillEntry(
          name: installedName,
          installedAt: DateTime.now().toUtc(),
          contentHash: installResult.contentHash,
        ),
      );

      // This skill was actually installed fresh, so we record it in the
      // response.
      installedInfos.add(
        InstalledSkillInfo(
          ideName: ide.cliName,
          skillName: skill.skillName,
          sourceUri: skill.sourceUri,
          isGlobal: skill.isGlobal,
        ),
      );

      // update local/global manifests for gitRepos so that we have a back
      // link from each gitRepo to where its skills were installed, for
      // cleanup later on.
      if (skill.gitUrl case var gitUrl?) {
        final installLocation = p.join(
          rootPath,
          ide.skillsRelativePath,
          installedName,
        );

        if (skill.isGlobal) {
          final index = updatedGlobalConfig.gitRepos.indexWhere(
            (r) => r.cloneUrl == gitUrl,
          );
          if (index >= 0) {
            final repo = updatedGlobalConfig.gitRepos[index];
            updatedGlobalConfig = GlobalConfig(
              gitRepos: [
                ...updatedGlobalConfig.gitRepos.sublist(0, index),
                repo.withInstall(installLocation),
                ...updatedGlobalConfig.gitRepos.sublist(index + 1),
              ],
            );
          }
        }
      }
    }

    return _PackageInstallResult(
      manifest: updatedManifest,
      globalConfig: updatedGlobalConfig,
      updatedSkillEntries: updatedSkillEntries,
      installedInfos: installedInfos,
    );
  }

  /// Cleans up any packages that were in the manifest but no longer exist
  /// in the skills list at all.
  ///
  /// If [packageNames] is not empty, then we will only consider the given
  /// packages for cleanup.
  Future<SkillManifest> _cleanupMissingPackages({
    required Ide ide,
    required String rootPath,
    required Map<String, Map<String, ScannedSkill>> skillsBySource,
    required SkillManifest manifest,
    required Set<String>? selectedSkills,
    required IdeAdapter adapter,
    required Set<String> sourceUris,
  }) async {
    var updatedManifest = manifest;
    final allPkgs = updatedManifest.sourceUrisForIde(ide.cliName).keys.toSet();
    final missingPkgs = allPkgs.difference(skillsBySource.keys.toSet());

    for (final pkgName in missingPkgs) {
      if (sourceUris.isNotEmpty && !sourceUris.contains(pkgName)) {
        continue;
      }

      final existingEntry = updatedManifest.sourceUrisForIde(
        ide.cliName,
      )[pkgName]!;
      final skippedSkills = <String>{};

      for (final existing in existingEntry.skills) {
        if (!existing.isInstalled) continue;
        if (selectedSkills != null && !selectedSkills.contains(existing.name)) {
          skippedSkills.add(existing.name);
        } else {
          if (!await adapter.removeSkill(existing.name)) {
            skippedSkills.add(existing.name);
          }
        }
      }

      if (skippedSkills.isNotEmpty) {
        _logOrphanedSkills(skippedSkills, adapter, rootPath);
        final keptSkills = existingEntry.skills
            .where((s) => skippedSkills.contains(s.name))
            .toList();
        updatedManifest = updatedManifest.withSourceUri(
          ide.cliName,
          pkgName,
          SkillsEntry(skills: keptSkills),
        );
      } else {
        updatedManifest = updatedManifest.withoutSourceUri(
          ide.cliName,
          pkgName,
        );
      }
    }
    return updatedManifest;
  }

  /// Removes skills for [ide] from [manifest].
  ///
  /// If [sourceUris] is not empty, only those sources skills are removed.
  /// If [skillNames] is not empty, only those specific skills are removed.
  Future<SkillRemoveResult> removeSkillsForIde({
    required Ide ide,
    required String rootPath,
    required SkillManifest manifest,
    Set<String> sourceUris = const {},
    Set<String> skillNames = const {},
  }) async {
    final adapter = createIdeAdapter(ide, rootPath, _dialogSupport);
    final removed = <RemovedSkillInfo>[];

    final sourceUriInstalls = manifest.sourceUrisForIde(ide.cliName);

    for (final MapEntry(key: sourceUri, value: SkillsEntry(skills: skills))
        in sourceUriInstalls.entries) {
      if (sourceUris.isNotEmpty && !sourceUris.contains(sourceUri)) {
        continue;
      }

      if (skillNames.isEmpty) {
        manifest = manifest.withoutSourceUri(ide.cliName, sourceUri);
        for (final skill in skills) {
          await adapter.removeSkill(skill.name);
          removed.add(
            RemovedSkillInfo(ideName: ide.cliName, skillName: skill.name),
          );
        }
      } else {
        final skillsToRemove = skills
            .where((s) => skillNames.contains(s.name))
            .toList();
        final skillsToKeep = skills
            .where((s) => !skillNames.contains(s.name))
            .toList();

        if (skillsToRemove.isNotEmpty) {
          for (final skill in skillsToRemove) {
            await adapter.removeSkill(skill.name);
            removed.add(
              RemovedSkillInfo(ideName: ide.cliName, skillName: skill.name),
            );
          }

          if (skillsToKeep.isEmpty) {
            manifest = manifest.withoutSourceUri(ide.cliName, sourceUri);
          } else {
            manifest = manifest.withSourceUri(
              ide.cliName,
              sourceUri,
              SkillsEntry(skills: skillsToKeep),
            );
          }
        }
      }
    }
    return SkillRemoveResult(
      manifest: manifest,
      removedCount: removed.length,
      removed: removed,
    );
  }

  /// Removes all skills for all IDEs in [manifest].
  /// Returns the updated (empty) manifest.
  Future<SkillManifest> removeAllSkills({
    required String rootPath,
    required SkillManifest manifest,
  }) async {
    var updated = manifest;
    for (final ideName in manifest.allIdes.toList()) {
      final ide = Ide.fromCliName(ideName);
      if (ide == null) continue;
      final result = await removeSkillsForIde(
        ide: ide,
        rootPath: rootPath,
        manifest: updated,
      );
      updated = result.manifest;
    }
    return updated;
  }
}
