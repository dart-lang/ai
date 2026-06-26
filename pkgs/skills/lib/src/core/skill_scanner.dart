import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'package_resolver.dart';

/// A scanned skill.
class ScannedSkill {
  /// The package name if this skill came from a pub dependency.
  final String? packageName;

  /// The git repo URL if this skill came from a git repo.
  final String? gitUrl;

  final String skillName;

  /// Nullable because of "orphaned" skills, which are a subtype of these skills
  /// and were previously installed [ScannedSkill]s which no longer exist in the
  /// source package/repo, and thus don't have a path.
  final String? skillPath;

  final bool isGlobal;

  const ScannedSkill({
    this.packageName,
    this.gitUrl,
    required this.skillName,
    required this.skillPath,
    this.isGlobal = false,
  });

  String get sourceUri => gitUrl ?? 'package:$packageName';
}

/// Scans resolved packages for skills/ directories containing Agent Skills.
class SkillScanner {
  final Logger logger;

  SkillScanner(this.logger);

  /// Scans all [packages] for skills directories and returns found skills.
  Future<List<ScannedSkill>> scan(List<ResolvedPackage> packages) async {
    final skills = <ScannedSkill>[];

    for (final package in packages) {
      final packageSkills = await scanPackage(package);
      skills.addAll(packageSkills);
    }

    return skills;
  }

  /// Scans a single [package] for its skills/ directory.
  ///
  /// Only includes skills whose directory name starts with the package name
  /// followed by a hyphen (e.g., package `serverpod` must have skills named
  /// `serverpod-*`). Skills that don't match are skipped with a warning.
  Future<List<ScannedSkill>> scanPackage(ResolvedPackage package) async {
    final skillsDir = Directory(p.join(package.rootPath, 'skills'));
    if (!await skillsDir.exists()) return [];

    final prefix = '${package.name}-';
    final skills = <ScannedSkill>[];

    await for (final entity in skillsDir.list()) {
      if (entity is! Directory) continue;

      final skillName = p.basename(entity.path);

      final skillMdFile = File(p.join(entity.path, 'SKILL.md'));
      if (!await skillMdFile.exists()) continue;

      if (!skillName.startsWith(prefix)) {
        logger.warning(
          'Skipping skill "$skillName" in ${package.name} '
          '-- name must start with "${package.name}-"',
        );
        continue;
      }

      skills.add(
        ScannedSkill(
          packageName: package.name,
          skillName: skillName,
          skillPath: entity.path,
        ),
      );
    }

    return skills;
  }
}
