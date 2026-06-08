import 'package:path/path.dart' as p;
import '../ide/ide.dart';
import '../ide/adapters/agent_skills_adapter.dart';
import '../ide/ide_adapter_factory.dart';
import '../models/global_config.dart';
import '../models/skill_manifest.dart';
import 'skill_scanner.dart';
import 'dialog_support.dart';

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
  final String packageName;
  final String? registryUrl;
  final bool isGlobal;

  const InstalledSkillInfo({
    required this.ideName,
    required this.skillName,
    required this.packageName,
    this.registryUrl,
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

/// Service for installing and removing skills across IDEs.
class SkillInstaller {
  final DialogSupport? _dialogSupport;

  SkillInstaller(this._dialogSupport);

  /// Installs [skills] for the given [ide] at [rootPath], updating [manifest].
  /// Removes existing skills for each package before reinstalling.
  Future<SkillInstallResult?> installSkillsForIde({
    required Ide ide,
    required String rootPath,
    required List<ScannedSkill> skills,
    required SkillManifest manifest,
    required GlobalConfig globalConfig,
  }) async {
    final adapter = createIdeAdapter(ide, rootPath, _dialogSupport);
    if (adapter is AgentSkillsAdapter) {
      if (!await adapter.performMigrations(manifest)) {
        return null;
      }
    }
    await adapter.ensureSkillsDirectory();

    final skillsByPackage = <String, Map<String, ScannedSkill>>{};
    for (final skill in skills) {
      // de-dupe skills by name, we can find multiple versions of a package
      // which can result in duplicates.
      skillsByPackage.putIfAbsent(
          skill.packageName, () => {})[skill.skillName] ??= skill;
    }

    var updatedManifest = manifest;
    final installed = <InstalledSkillInfo>[];

    for (final entry in skillsByPackage.entries) {
      final pkgName = entry.key;
      final pkgSkills = entry.value.values;

      final existingPkgs = updatedManifest.packagesForIde(ide.cliName);
      final existingEntry = existingPkgs[pkgName];
      if (existingEntry != null) {
        for (final existing in existingEntry.skills) {
          await adapter.removeSkill(existing.name);
        }
      }

      final installedSkills = <InstalledSkillEntry>[];
      var updatedGlobalConfig = globalConfig;

      for (final skill in pkgSkills) {
        final installedName = await adapter.installSkill(skill);
        installedSkills.add(
          InstalledSkillEntry(
            name: installedName,
            installedAt: DateTime.now().toUtc(),
          ),
        );
        installed.add(
          InstalledSkillInfo(
            ideName: ide.cliName,
            skillName: skill.skillName,
            packageName: pkgName,
            registryUrl: skill.registryUrl,
            isGlobal: skill.isGlobal,
          ),
        );

        if (skill.registryUrl case var registryUrl?) {
          final installLocation =
              p.join(rootPath, ide.skillsRelativePath, installedName);

          if (skill.isGlobal) {
            final index = updatedGlobalConfig.registries
                .indexWhere((r) => r.cloneUrl == registryUrl);
            if (index >= 0) {
              final repo = updatedGlobalConfig.registries[index];
              updatedGlobalConfig = GlobalConfig(
                registries: [
                  ...updatedGlobalConfig.registries.sublist(0, index),
                  repo.withInstall(installLocation),
                  ...updatedGlobalConfig.registries.sublist(index + 1),
                ],
              );
            }
          } else {
            final index = updatedManifest.registries
                .indexWhere((r) => r.cloneUrl == registryUrl);
            if (index >= 0) {
              final repo = updatedManifest.registries[index];
              updatedManifest = SkillManifest(
                version: updatedManifest.version,
                installations: updatedManifest.installations,
                registries: [
                  ...updatedManifest.registries.sublist(0, index),
                  repo.withInstall(installLocation),
                  ...updatedManifest.registries.sublist(index + 1),
                ],
              );
            }
          }
        }
      }

      updatedManifest = updatedManifest.withPackage(
        ide.cliName,
        pkgName,
        PackageSkillsEntry(skills: installedSkills),
      );
      globalConfig = updatedGlobalConfig;
    }

    return SkillInstallResult(
        manifest: updatedManifest,
        globalConfig: globalConfig,
        installed: installed);
  }

  /// Removes skills for [ide] from [manifest].
  ///
  /// If [packageNames] is not empty, only those packages skills are removed.
  /// If [skillNames] is not empty, only those specific skills are removed.
  Future<SkillRemoveResult> removeSkillsForIde({
    required Ide ide,
    required String rootPath,
    required SkillManifest manifest,
    Set<String> packageNames = const {},
    Set<String> skillNames = const {},
  }) async {
    final adapter = createIdeAdapter(ide, rootPath, _dialogSupport);
    final removed = <RemovedSkillInfo>[];

    final pkgs = manifest.packagesForIde(ide.cliName);

    for (final MapEntry(key: pkgName, value: PackageSkillsEntry(skills: skills))
        in pkgs.entries) {
      if (packageNames.isNotEmpty && !packageNames.contains(pkgName)) {
        continue;
      }

      if (skillNames.isEmpty) {
        manifest = manifest.withoutPackage(ide.cliName, pkgName);
        for (final skill in skills) {
          await adapter.removeSkill(skill.name);
          removed.add(
            RemovedSkillInfo(ideName: ide.cliName, skillName: skill.name),
          );
        }
      } else {
        final skillsToRemove =
            skills.where((s) => skillNames.contains(s.name)).toList();
        final skillsToKeep =
            skills.where((s) => !skillNames.contains(s.name)).toList();

        if (skillsToRemove.isNotEmpty) {
          for (final skill in skillsToRemove) {
            await adapter.removeSkill(skill.name);
            removed.add(
              RemovedSkillInfo(ideName: ide.cliName, skillName: skill.name),
            );
          }

          if (skillsToKeep.isEmpty) {
            manifest = manifest.withoutPackage(ide.cliName, pkgName);
          } else {
            manifest = manifest.withPackage(
              ide.cliName,
              pkgName,
              PackageSkillsEntry(skills: skillsToKeep),
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
