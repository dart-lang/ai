import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/dialog_support.dart';
import '../../core/hash_utils.dart';
import '../../core/skill_scanner.dart';
import '../../models/skill_manifest.dart';
import '../agent_adapter.dart';

/// Base adapter for agents that support the Agent Skills standard natively.
///
/// Copies the full skill directory (SKILL.md + scripts/ + references/ + assets/)
/// using the skill's own name as the target directory name.
abstract class AgentSkillsAdapter extends AgentAdapter {
  @override
  final String skillsDirectory;
  final DialogSupport? dialogSupport;

  AgentSkillsAdapter(super.agent, this.skillsDirectory, {this.dialogSupport});

  @override
  Future<void> ensureSkillsDirectory() async {
    await Directory(skillsDirectory).create(recursive: true);
  }

  /// Performs any migrations needed for this agent.
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
    assert(skill.skillPath != null, 'Cannot install a skill without a path');
    await _copyDirectory(Directory(skill.skillPath!), targetDir);
    final hash = await computeInstalledSkillHash(skill.skillName);
    if (hash == null) {
      throw StateError('Failed to install skill at ${targetDir.path}.');
    }
    return (name: skill.skillName, contentHash: hash);
  }

  @override
  Future<bool> removeSkill(String skillName) async {
    final targetDir = Directory(p.join(skillsDirectory, skillName));
    if (!await targetDir.exists()) {
      return true;
    }

    // Prompting is handled by the calling layer (e.g. `skills get` dialog).
    await targetDir.delete(recursive: true);
    return true;
  }

  @override
  Future<String?> computeInstalledSkillHash(String skill) async =>
      await tryCalculateDirectoryHash(
        Directory(p.join(skillsDirectory, skill)),
      );

  @override
  Future<String?> computeSourceSkillHash(Directory skillDir) async =>
      await tryCalculateDirectoryHash(skillDir);

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
