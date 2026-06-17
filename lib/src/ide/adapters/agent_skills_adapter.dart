import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/dialog_support.dart';
import '../../core/hash_utils.dart';
import '../../core/skill_scanner.dart';
import '../../models/skill_manifest.dart';
import '../ide_adapter.dart';

/// Base adapter for IDEs that support the Agent Skills standard natively.
///
/// Copies the full skill directory (SKILL.md + scripts/ + references/ + assets/)
/// using the skill's own name as the target directory name.
abstract class AgentSkillsAdapter implements IdeAdapter {
  @override
  final String skillsDirectory;
  final DialogSupport? dialogSupport;

  AgentSkillsAdapter(this.skillsDirectory, {this.dialogSupport});

  @override
  Future<void> ensureSkillsDirectory() async {
    await Directory(skillsDirectory).create(recursive: true);
  }

  /// Performs any migrations needed for this IDE.
  ///
  /// Returns false if the operation was aborted by the user or failed,
  /// true if it succeeded.
  Future<bool> performMigrations(SkillManifest manifest) async => true;

  @override
  Future<InstallSkillResult> installSkill(ScannedSkill skill) async {
    final targetDir = Directory(p.join(skillsDirectory, skill.skillName));

    if (await targetDir.exists()) {
      await targetDir.delete(recursive: true);
    }
    await targetDir.create(recursive: true);

    await _copyDirectory(Directory(skill.skillPath), targetDir);

    return (
      name: skill.skillName,
      contentHash: await calculateDirectoryHash(targetDir),
    );
  }

  @override
  Future<bool> removeSkill(
    String skillName, {
    String? originalHash,
    bool force = false,
  }) async {
    final targetDir = Directory(p.join(skillsDirectory, skillName));
    if (!await targetDir.exists()) {
      return true;
    }

    if (!await promptOverwriteIfChanged(
      dialogSupport: dialogSupport,
      skillName: skillName,
      originalHash: originalHash,
      currentHash: await calculateDirectoryHash(targetDir),
      force: force,
      logger: logger,
    )) {
      return false;
    }

    await targetDir.delete(recursive: true);
    return true;
  }

  Future<void> _copyDirectory(Directory source, Directory target) async {
    await for (final entity in source.list(recursive: false)) {
      final targetPath = p.join(target.path, p.basename(entity.path));

      if (entity is File) {
        await entity.copy(targetPath);
      } else if (entity is Directory) {
        final newDir = Directory(targetPath);
        await newDir.create(recursive: true);
        await _copyDirectory(entity, newDir);
      }
    }
  }
}
