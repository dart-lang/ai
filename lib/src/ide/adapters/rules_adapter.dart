import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../../core/dialog_support.dart';
import '../../core/hash_utils.dart';
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
  final Logger logger = Logger('RulesAdapter');

  @override
  final String skillsDirectory;

  final DialogSupport? dialogSupport;

  /// File extension for rule files (e.g., '.md', '.instructions.md').
  final String fileExtension;

  /// Optional prefix added before the markdown body.
  final String Function(SkillMetadata metadata)? headerBuilder;

  RulesAdapter({
    required this.skillsDirectory,
    this.dialogSupport,
    this.fileExtension = '.md',
    this.headerBuilder,
  });

  @override
  Future<void> ensureSkillsDirectory() async {
    await Directory(skillsDirectory).create(recursive: true);
  }

  @override
  Future<InstallSkillResult> installSkill(
    ScannedSkill skill,
  ) async {
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

    final hash = await tryCalculateFileHash(targetFile);
    if (hash == null) {
      throw StateError(
          'Failed to install skill ${skill.skillName} from ${skill.skillPath}');
    }

    return (name: skill.skillName, contentHash: hash);
  }

  @override
  Future<bool> removeSkill(String skillName,
      {String? originalHash, bool force = false}) async {
    final targetFile = File(
      p.join(skillsDirectory, '$skillName$fileExtension'),
    );
    if (!await targetFile.exists()) {
      return true;
    }

    final currentHash = await tryCalculateFileHash(targetFile);
    if (currentHash == null) {
      throw StateError(
          'Failed to calculate hash for $skillName at ' '${targetFile.path}');
    }
    if (!await promptOverwriteIfChanged(
      dialogSupport: dialogSupport,
      skillName: skillName,
      originalHash: originalHash,
      currentHash: currentHash,
      force: force,
      logger: logger,
    )) {
      return false;
    }

    await targetFile.delete();
    return true;
  }
}
