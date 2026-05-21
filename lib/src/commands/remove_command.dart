import '../core/skill_installer.dart';
import '../ide/ide.dart';
import '../models/skill_manifest.dart';
import 'options.dart';
import 'skills_command.dart';
import 'package:skills/src/core/dialog_support.dart';

/// Removes managed skills.
class RemoveCommand extends SkillsCommand {
  @override
  final String name = 'remove';

  @override
  final String description = 'Remove managed skills.';

  final DialogSupport? _dialogSupport;

  RemoveCommand({
    DialogSupport? dialogSupport,
  }) : _dialogSupport = dialogSupport {
    addIdeOption(argParser);
  }

  @override
  Future<void> run() async {
    final workspace = await resolveWorkspace();
    final rootPath = workspace.rootPath;

    final loaded = await SkillManifest.loadOrEmptyFromRoot(rootPath);

    if (loaded.isEmpty) {
      logger.info('No managed skills found.');
      return;
    }

    var manifest = loaded;

    final packageName = packageNameArg;

    // Determine which IDEs to remove from: --ide narrows to one,
    // otherwise all IDEs in the manifest.
    final List<Ide> targetIdes;
    final parsedIde = parseIdeOption(argResults);
    if (parsedIde != null) {
      targetIdes = [parsedIde];
    } else {
      targetIdes = manifest.allIdes
          .map((name) => Ide.fromCliName(name))
          .whereType<Ide>()
          .toList();
    }

    final installer = SkillInstaller(_dialogSupport);
    var totalRemoved = 0;

    for (final ide in targetIdes) {
      final result = await installer.removeSkillsForIde(
        ide: ide,
        rootPath: rootPath,
        manifest: manifest,
        packageName: packageName,
      );
      manifest = result.manifest;
      totalRemoved += result.removedCount;
      for (final info in result.removed) {
        logger.info('  [${info.ideName}] Removed ${info.skillName}');
      }
    }

    if (manifest.isEmpty) {
      await SkillManifest.cleanupDir(rootPath);
    } else {
      await manifest.save(manifestFile(rootPath));
    }

    if (packageName != null) {
      logger.info('Removed skills from $packageName.');
    } else {
      logger.info('Removed $totalRemoved managed skill(s).');
    }
  }
}
