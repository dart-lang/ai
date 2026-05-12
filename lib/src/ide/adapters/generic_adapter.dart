import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:skills/src/core/dialog_support.dart';

import '../../models/skill_manifest.dart';
import '../ide.dart';
import 'agent_skills_adapter.dart';

/// Generic agent IDE adapter for Antigravity, Codex, or generic.
///
/// Installs skills to `.agents/skills/<pkg>-<skill>/SKILL.md`.
class GenericAdapter extends AgentSkillsAdapter {
  final String _projectPath;
  final DialogSupport? _dialogSupport;

  GenericAdapter(this._projectPath, this._dialogSupport)
      : super(Ide.generic.skillsPath(_projectPath));

  @override
  Future<bool> performMigrations(SkillManifest manifest) async {
    return migrateSkillsDir(manifest);
  }

  @visibleForTesting
  Future<bool> migrateSkillsDir(SkillManifest manifest) async {
    final oldDir = Directory(p.join(_projectPath, '.agent'));
    final oldSkillsDir = Directory(p.join(oldDir.path, 'skills'));
    final newDir = Directory(p.join(_projectPath, '.agents'));
    final newSkillsDir = Directory(p.join(newDir.path, 'skills'));

    final genericPkgs = manifest.packagesForIde('generic');
    final manifestSkills = <String>{};
    for (final pkg in genericPkgs.values) {
      for (final skill in pkg.skills) {
        manifestSkills.add(skill.name);
      }
    }

    if (await oldSkillsDir.exists()) {
      bool hasManifestSkillsInOldDir = false;
      await for (final entity in oldSkillsDir.list(recursive: false)) {
        if (entity is Directory) {
          final name = p.basename(entity.path);
          if (manifestSkills.contains(name)) {
            hasManifestSkillsInOldDir = true;
            break;
          }
        }
      }

      if (!hasManifestSkillsInOldDir) {
        return true;
      }
      // Default is to only move known skills that we installed.
      bool moveAll = false;

      // In interactive mode, we give a few more options for the migration.
      if (_dialogSupport case var dialogSupport?) {
        final result = await dialogSupport.showSingleSelectDialog([
          'Move ONLY managed skills to .agents/skills',
          'Move ALL skills to .agents/skills',
          'Leave .agent/skills in place (may result in duplicate skills)',
          'Abort'
        ],
            title:
                'Found an old `.agent/skills` directory with managed skills. '
                'What would you like to do?');

        if (result == 2) {
          // Leave old skills in place
          return true;
        } else if (result == null || result > 2) {
          // Abort
          return false;
        } else if (result == 1) {
          moveAll = true;
        }
      }

      if (!await newSkillsDir.exists()) {
        await newSkillsDir.create(recursive: true);
      }

      await for (final entity in oldSkillsDir.list(recursive: false)) {
        final name = p.basename(entity.path);
        if (!moveAll && !manifestSkills.contains(name)) {
          continue;
        }

        final targetPath = p.join(newSkillsDir.path, p.basename(entity.path));
        if (await Directory(targetPath).exists() ||
            await File(targetPath).exists()) {
          if (entity is Directory) {
            await Directory(targetPath).delete(recursive: true);
          } else if (entity is File) {
            await File(targetPath).delete();
          }
        }
        await entity.rename(targetPath);
      }

      // Delete old skills dir if empty
      if (await oldSkillsDir.list().isEmpty) {
        await oldSkillsDir.delete();
      }

      // Clean up old .agent dir if empty
      if (await oldDir.exists() && await oldDir.list().isEmpty) {
        await oldDir.delete();
      }
    }
    return true;
  }
}
