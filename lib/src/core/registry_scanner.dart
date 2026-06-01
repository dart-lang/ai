import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'registry_repos.dart';
import 'skill_scanner.dart';

/// Scans `.dart_tool/skills/repos/<owner>/<repo>/skills/` for skill directories.
///
/// Uses each repo's [RegistrySkillLayout] to find skills:
/// - [RegistrySkillLayout.flat]: direct subdirs of `skills/` with SKILL.md;
///   dir name must contain a hyphen; package = segment before first hyphen.
/// - [RegistrySkillLayout.groupedByPackage]: `skills/<package>/<skill-dir>/`;
///   package = middle segment, skill name = leaf dir name.
class RegistryScanner {
  static final _logger = Logger('RegistryScanner');

  const RegistryScanner();

  /// Scans all [repos] under [rootPath] and returns [ScannedSkill]s.
  ///
  /// Scans all [repos] under [rootPath] and returns [ScannedSkill]s.
  Future<List<ScannedSkill>> scan(
    String rootPath, {
    required bool isGlobal,
    List<RegistryRepo> repos = const [],
  }) async {
    final skills = <ScannedSkill>[];
    final reposPath = registryReposPath(rootPath);
    final reposDir = Directory(reposPath);
    if (!await reposDir.exists()) return skills;

    for (final repo in repos) {
      final repoDir = Directory(p.join(reposPath, repo.pathSegment));
      if (!await repoDir.exists()) continue;

      final skillsDir = Directory(p.join(repoDir.path, 'skills'));
      if (!await skillsDir.exists()) continue;

      final layout = await _inferLayout(skillsDir);
      if (layout == null) {
        _logger.warning('Error: Repository ${repo.cloneUrl} does not follow a '
            'recognized skill layout.');
        continue;
      }

      switch (layout) {
        case RegistrySkillLayout.flat:
          skills.addAll(await _scanFlat(skillsDir, repo.cloneUrl, isGlobal));
          break;
        case RegistrySkillLayout.groupedByPackage:
          skills.addAll(
              await _scanGroupedByPackage(skillsDir, repo.cloneUrl, isGlobal));
          break;
      }
    }
    return skills;
  }

  /// Infers the skill layout by inspecting the contents of [skillsDir].
  Future<RegistrySkillLayout?> _inferLayout(Directory skillsDir) async {
    await for (final entity in skillsDir.list()) {
      if (entity is Directory) {
        final skillMdFile = File(p.join(entity.path, 'SKILL.md'));
        if (await skillMdFile.exists()) {
          return RegistrySkillLayout.flat;
        }

        await for (final subEntity in entity.list()) {
          if (subEntity is Directory) {
            final subSkillMdFile = File(p.join(subEntity.path, 'SKILL.md'));
            if (await subSkillMdFile.exists()) {
              return RegistrySkillLayout.groupedByPackage;
            }
          }
        }
      }
    }
    return null;
  }

  /// Flat layout: skills directly under [skillsDir]; dir name = `<package>-<suffix>`.
  Future<List<ScannedSkill>> _scanFlat(
      Directory skillsDir, String registryUrl, bool isGlobal) async {
    final skills = <ScannedSkill>[];
    await for (final entity in skillsDir.list()) {
      if (entity is! Directory) continue;

      final skillName = p.basename(entity.path);
      final skillMdFile = File(p.join(entity.path, 'SKILL.md'));
      if (!await skillMdFile.exists()) continue;

      final hyphenIndex = skillName.indexOf('-');
      if (hyphenIndex <= 0) continue;

      final packageName = skillName.substring(0, hyphenIndex);
      skills.add(
        ScannedSkill(
          packageName: packageName,
          skillName: skillName,
          skillPath: entity.path,
          registryUrl: registryUrl,
          isGlobal: isGlobal,
        ),
      );
    }
    return skills;
  }

  /// Grouped layout: skills under [skillsDir] with one level per package name,
  /// then one level per skill directory (e.g. skills/riverpod/riverpod-get-started).
  Future<List<ScannedSkill>> _scanGroupedByPackage(
      Directory skillsDir, String registryUrl, bool isGlobal) async {
    final skills = <ScannedSkill>[];
    await for (final packageEntity in skillsDir.list()) {
      if (packageEntity is! Directory) continue;

      final packageName = p.basename(packageEntity.path);
      await for (final entity in packageEntity.list()) {
        if (entity is! Directory) continue;

        final skillName = p.basename(entity.path);
        final skillMdFile = File(p.join(entity.path, 'SKILL.md'));
        if (!await skillMdFile.exists()) continue;

        skills.add(
          ScannedSkill(
            packageName: packageName,
            skillName: skillName,
            skillPath: entity.path,
            registryUrl: registryUrl,
            isGlobal: isGlobal,
          ),
        );
      }
    }
    return skills;
  }
}
