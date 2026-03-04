import 'dart:io';

import 'package:path/path.dart' as p;

import 'package_resolver.dart';

/// A skill found within a package's skills/ directory.
class ScannedSkill {
  final String packageName;
  final String skillName;
  final String skillPath;

  const ScannedSkill({
    required this.packageName,
    required this.skillName,
    required this.skillPath,
  });
}

/// Scans resolved packages for skills/ directories containing Agent Skills.
class SkillScanner {
  const SkillScanner();

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
        stderr.writeln(
          'Warning: Skipping skill "$skillName" in ${package.name} '
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
