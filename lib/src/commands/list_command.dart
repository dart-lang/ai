import 'dart:io';

import '../models/skill_manifest.dart';
import 'skills_command.dart';

/// Lists all installed managed skills.
class ListCommand extends SkillsCommand {
  @override
  final String name = 'list';

  @override
  final String description = 'List installed managed skills.';

  @override
  Future<void> run() async {
    final workspace = await resolveWorkspace();
    final rootPath = workspace.rootPath;

    final manifest = await SkillManifest.load(manifestFile(rootPath));

    if (manifest == null || manifest.isEmpty) {
      stdout.writeln('No managed skills installed.');
      return;
    }

    stdout.writeln('Installed skills:');
    stdout.writeln();

    for (final ide in manifest.allIdes) {
      final pkgs = manifest.packagesForIde(ide);
      if (pkgs.isEmpty) continue;

      stdout.writeln('  $ide:');
      for (final entry in pkgs.entries) {
        stdout.writeln('    ${entry.key}:');
        for (final skill in entry.value.skills) {
          stdout.writeln('      - ${skill.name}');
        }
      }
    }
  }
}
