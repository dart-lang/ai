import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/skill_scanner.dart';
import '../../models/skill_metadata.dart';
import '../ide_adapter.dart';

/// Shared header for rules-based adapters (Claude, Cline).
String defaultManagedHeader(SkillMetadata metadata) {
  return '<!-- managed by skills CLI -->\n'
      '<!-- skill: ${metadata.name} -->\n\n';
}

/// Base adapter for IDEs that use a rules/instructions format.
///
/// Transforms SKILL.md into the IDE's native rule file format.
class RulesAdapter implements IdeAdapter {
  @override
  final String skillsDirectory;

  /// File extension for rule files (e.g., '.md', '.instructions.md').
  final String fileExtension;

  /// Optional prefix added before the markdown body.
  final String Function(SkillMetadata metadata)? headerBuilder;

  RulesAdapter({
    required this.skillsDirectory,
    this.fileExtension = '.md',
    this.headerBuilder,
  });

  @override
  Future<void> ensureSkillsDirectory() async {
    await Directory(skillsDirectory).create(recursive: true);
  }

  @override
  Future<String> installSkill(ScannedSkill skill) async {
    final skillMdFile = File(p.join(skill.skillPath, 'SKILL.md'));
    final metadata = await SkillMetadata.parse(skillMdFile);

    final buffer = StringBuffer();
    if (headerBuilder != null) {
      buffer.write(headerBuilder!(metadata));
    }
    buffer.write(metadata.body);
    if (!metadata.body.endsWith('\n')) {
      buffer.writeln();
    }

    final targetFile = File(
      p.join(skillsDirectory, '${skill.skillName}$fileExtension'),
    );
    await targetFile.writeAsString(buffer.toString());

    return skill.skillName;
  }

  @override
  Future<void> removeSkill(String skillName) async {
    final targetFile = File(
      p.join(skillsDirectory, '$skillName$fileExtension'),
    );
    if (await targetFile.exists()) {
      await targetFile.delete();
    }
  }
}
