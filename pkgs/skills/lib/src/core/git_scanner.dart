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
/// Recursively searches for `SKILL.md` files within the repository.
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

      skills.addAll(await _scanRepo(repoDir, repo.cloneUrl, isGlobal));
    }
    return skills;
  }

  Future<List<ScannedSkill>> _scanRepo(
    Directory repoDir,
    String gitUrl,
    bool isGlobal,
  ) async {
    final skills = <ScannedSkill>[];
    await for (final entity in repoDir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || p.basename(entity.path) != 'SKILL.md') continue;

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

      skills.add(
        ScannedSkill(
          gitUrl: gitUrl,
          skillName: skillName,
          skillPath: skillDir.path,
          isGlobal: isGlobal,
        ),
      );
    }
    return skills;
  }
}
