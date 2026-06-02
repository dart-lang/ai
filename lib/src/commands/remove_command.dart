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

    var packagesToRemove = packageNamesArg?.toSet();

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

    if (packagesToRemove == null) {
      final packagesWithSkills = <String>{};
      for (final ide in targetIdes) {
        packagesWithSkills.addAll(manifest.packagesForIde(ide.cliName).keys);
      }
      final packagesList = packagesWithSkills.toList()..sort();

      if (packagesList.isEmpty) {
        logger.info('No skills found to remove.');
        return;
      }

      if (_dialogSupport != null) {
        final selectedIndices = await _dialogSupport.showMultiSelectDialog(
          packagesList,
          title: 'Select packages to remove skills for:',
        );
        if (selectedIndices != null) {
          packagesToRemove =
              selectedIndices.map((i) => packagesList[i]).toSet();
        } else {
          logger.info('Removal aborted.');
          return;
        }
      } else {
        logger.info('Packages with installed skills:');
        for (final pkg in packagesList) {
          logger.info('  $pkg');
        }
        logger.info('Rerun with trailing arguments for each package you want '
            'to remove skills for, or `all` to remove all skills.');
        return;
      }
    }

    if (packagesToRemove.isEmpty) {
      logger.info('No packages selected for removal.');
      return;
    }

    final installer = SkillInstaller(_dialogSupport);
    var totalRemoved = 0;

    for (final ide in targetIdes) {
      final result = await installer.removeSkillsForIde(
        ide: ide,
        rootPath: rootPath,
        manifest: manifest,
        packageNames: packagesToRemove,
      );
      manifest = result.manifest;
      totalRemoved += result.removedCount;
      for (final info in result.removed) {
        logger.info('  [${info.ideName}] Removed ${info.skillName}');
      }
    }

    await manifest.save(manifestFile(rootPath));
    if (manifest.isEmpty) {
      await SkillManifest.cleanup(rootPath);
    }

    if (totalRemoved > 0) {
      logger.info('Removed $totalRemoved skill(s) from '
          '${packagesToRemove.join(', ')}.');
    } else {
      logger.info('Removed $totalRemoved managed skill(s).');
    }
  }
}
