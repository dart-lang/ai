// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'constants.dart';
import 'frontmatter.dart';
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

  /// Relative path within the source repo or package (e.g. "skills/my-skill").
  final String? path;

  const ScannedSkill({
    this.packageName,
    this.gitUrl,
    required this.skillName,
    required this.skillPath,
    this.isGlobal = false,
    this.path,
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

      SkillFrontmatter? frontmatter;
      try {
        frontmatter = SkillFrontmatter.fromSkillContent(
          await skillMdFile.readAsString(),
        );
      } on FormatException catch (e) {
        logger.warning(
          'Skipping skill at path ${entity.path} due to formatting '
          'error: $e',
        );
        continue;
      }
      if (frontmatter.isInternal && !shouldInstallInternalSkills) continue;

      if (!skillName.startsWith(prefix)) {
        logger.warning(
          'Skipping skill "$skillName" in ${package.name} '
          '-- name must start with "${package.name}-"',
        );
        continue;
      }

      final pathInPackage = p.relative(entity.path, from: package.rootPath);
      skills.add(
        ScannedSkill(
          packageName: package.name,
          skillName: skillName,
          skillPath: entity.path,
          path: pathInPackage,
        ),
      );
    }

    return skills;
  }
}
