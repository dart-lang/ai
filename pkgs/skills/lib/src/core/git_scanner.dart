// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:skills/src/core/constants.dart';

import 'frontmatter.dart';
import 'git_repos.dart';
import 'skill_scanner.dart';

/// Scans `.dart_tool/skills/repos/<encoded-url>/` for skill directories.
///
/// Recursively searches for `SKILL.md` files within the repository. The same
/// scan is used for directories linked with `skills link`.
class GitScanner {
  const GitScanner();

  static final _logger = Logger('GitScanner');

  /// Scans all [repos] under [rootPath] and returns [ScannedSkill]s.
  Future<List<ScannedSkill>> scan(
    String rootPath, {
    required bool isGlobal,
    List<GitRepo> repos = const [],
  }) async {
    final skills = <ScannedSkill>[];
    final reposPath = gitReposPath(rootPath);
    final reposDir = Directory(reposPath);
    if (!await reposDir.exists()) return skills;

    for (final repo in repos) {
      final repoDir = Directory(p.join(reposPath, repo.pathSegment));
      if (!await repoDir.exists()) continue;

      skills.addAll(
        await scanDirectory(repoDir, gitUrl: repo.cloneUrl, isGlobal: isGlobal),
      );
    }
    return skills;
  }

  /// Recursively scans [directory] for skills, attributing them to [gitUrl]
  /// or [linkedDirectory].
  Future<List<ScannedSkill>> scanDirectory(
    Directory directory, {
    String? gitUrl,
    String? linkedDirectory,
    bool isGlobal = false,
  }) async {
    final skills = <ScannedSkill>[];
    await _scanDirectory(
      directory,
      directory,
      gitUrl,
      linkedDirectory,
      isGlobal,
      skills,
    );
    return skills;
  }

  Future<void> _scanDirectory(
    Directory dir,
    Directory repoDir,
    String? gitUrl,
    String? linkedDirectory,
    bool isGlobal,
    List<ScannedSkill> skills,
  ) async {
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is Directory) {
        final name = p.basename(entity.path);
        if (name == 'third_party' || name.startsWith('.')) continue;
        await _scanDirectory(
          entity,
          repoDir,
          gitUrl,
          linkedDirectory,
          isGlobal,
          skills,
        );
      } else if (entity is File && p.basename(entity.path) == 'SKILL.md') {
        SkillFrontmatter? frontmatter;
        try {
          frontmatter = SkillFrontmatter.fromSkillContent(
            await entity.readAsString(),
          );
        } on FormatException catch (e) {
          _logger.warning(
            'Skipping skill at path ${entity.path} due to formatting '
            'error: $e',
          );
          continue;
        }
        if (frontmatter.isInternal && !shouldInstallInternalSkills) continue;

        final skillDir = entity.parent;
        final skillName = p.basename(skillDir.path);
        final pathInRepo = p
            .split(p.relative(skillDir.path, from: repoDir.path))
            .join('/');

        skills.add(
          ScannedSkill(
            gitUrl: gitUrl,
            linkedDirectory: linkedDirectory,
            skillName: skillName,
            skillPath: skillDir.path,
            isGlobal: isGlobal,
            path: pathInRepo,
          ),
        );
      }
    }
  }
}
