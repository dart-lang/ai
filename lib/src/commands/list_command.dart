import '../models/skill_manifest.dart';
import 'skills_command.dart';

/// Lists all installed managed skills.
class ListCommand extends SkillsCommand {
  @override
  final String name = 'list';

  @override
  final String description = 'List installed managed skills.';

  ListCommand();

  @override
  Future<void> run() async {
    final workspace = await resolveWorkspace();
    final rootPath = workspace.rootPath;

    final manifest = await SkillManifest.load(manifestFile(rootPath));

    if (manifest == null || manifest.isEmpty) {
      logger.info('No managed skills installed.');
      return;
    }

    final buffer = StringBuffer()
      ..writeln('Installed skills:')
      ..writeln();

    for (final ide in manifest.allIdes) {
      final pkgs = manifest.packagesForIde(ide);
      if (pkgs.isEmpty) continue;

      buffer.writeln('  $ide:');
      for (final entry in pkgs.entries) {
        buffer.writeln('    ${entry.key}:');
        for (final skill in entry.value.skills) {
          buffer.writeln('      - ${skill.name}');
        }
      }
    }

    logger.info(buffer.toString());
  }
}
