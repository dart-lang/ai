import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/skill_scanner.dart';
import '../ide_adapter.dart';

/// Base adapter for IDEs that support the Agent Skills standard natively.
///
/// Copies the full skill directory (SKILL.md + scripts/ + references/ + assets/)
/// using the skill's own name as the target directory name.
class AgentSkillsAdapter implements IdeAdapter {
  @override
  final String skillsDirectory;

  AgentSkillsAdapter(this.skillsDirectory);

  @override
  Future<void> ensureSkillsDirectory() async {
    await Directory(skillsDirectory).create(recursive: true);
  }

  @override
  Future<String> installSkill(ScannedSkill skill) async {
    final targetDir = Directory(p.join(skillsDirectory, skill.skillName));

    if (await targetDir.exists()) {
      await targetDir.delete(recursive: true);
    }
    await targetDir.create(recursive: true);

    await _copyDirectory(Directory(skill.skillPath), targetDir);

    return skill.skillName;
  }

  @override
  Future<void> removeSkill(String skillName) async {
    final targetDir = Directory(p.join(skillsDirectory, skillName));
    if (await targetDir.exists()) {
      await targetDir.delete(recursive: true);
    }
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
