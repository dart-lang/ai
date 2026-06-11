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
    argParser.addMultiOption(
      'package',
      abbr: 'p',
      help: 'Remove skills for these packages.',
    );
    argParser.addMultiOption(
      'skill',
      abbr: 's',
      help: 'Remove specific skills.',
    );
    argParser.addFlag(
      'all',
      abbr: 'a',
      help: 'Remove all managed skills.',
      negatable: false,
    );
  }

  @override
  Future<void> run() async {
    final argResults = this.argResults!;
    final workspace = await resolveWorkspace();
    final rootPath = workspace.rootPath;

    final loaded = await SkillManifest.loadOrEmptyFromRoot(rootPath);

    if (loaded.isEmpty) {
      logger.info('No managed skills found.');
      return;
    }

    var manifest = loaded;

    final packagesToRemove = argResults.multiOption('package').toSet();
    final skillsToRemove = argResults.multiOption('skill').toSet();
    final allFlag = argResults.flag('all');

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

    // Prompt the user for the packages to remove if possible and not given.
    if (_dialogSupport != null &&
        !allFlag &&
        packagesToRemove.isEmpty &&
        skillsToRemove.isEmpty) {
      final allPackages = {
        for (final ide in targetIdes)
          ...manifest.packagesForIde(ide.cliName).keys,
      }.toList()
        ..sort();
      final selectedIndices = await _dialogSupport.showMultiSelectDialog(
        allPackages,
        title: 'Select packages to remove skills for:',
      );
      if (selectedIndices != null) {
        packagesToRemove.addAll(selectedIndices.map((i) => allPackages[i]));
      } else {
        logger.info('Skill removal aborted.');
        return;
      }
      if (packagesToRemove.isEmpty) {
        logger.info('No packages selected for removal.');
        return;
      }
    }

    // Prompt the user for skills to remove if possible and not given.
    if (_dialogSupport != null && !allFlag && skillsToRemove.isEmpty) {
      // All the available skills filtered by selected packages
      final potentialSkills = {
        for (final ide in targetIdes)
          for (final MapEntry(key: package, value: entry)
              in manifest.packagesForIde(ide.cliName).entries)
            if (packagesToRemove.isEmpty || packagesToRemove.contains(package))
              ...entry.skills.map((skill) => skill.name)
      }.toList()
        ..sort();
      final selectedIndices = await _dialogSupport.showMultiSelectDialog(
        potentialSkills,
        title: 'Select skills to remove',
      );
      if (selectedIndices != null) {
        skillsToRemove.addAll(selectedIndices.map((i) => potentialSkills[i]));
      } else {
        logger.info('Skill removal aborted.');
        return;
      }

      if (skillsToRemove.isEmpty) {
        logger.info('No skills selected for removal.');
        return;
      }
    }

    // The fully filtered map of things to remove.
    final Map< /* IDE */ String, Map< /* Package */ String, PackageSkillsEntry>>
        filteredSkills = {
      for (final ide in targetIdes)
        ide.cliName: {
          for (final entry in manifest.packagesForIde(ide.cliName).entries)
            if (packagesToRemove.isEmpty ||
                packagesToRemove.contains(entry.key))
              entry.key: PackageSkillsEntry(skills: [
                for (final skill in entry.value.skills)
                  if (skillsToRemove.isEmpty ||
                      skillsToRemove.contains(skill.name))
                    skill,
              ])
        }
    };

    // If non-interactive and no arguments, list installed skills and exit
    if (_dialogSupport == null && skillsToRemove.isEmpty && !allFlag) {
      logger.info('Installed skills:');
      final installedSkillsAndIdes =
          < /* Skill name */ String, Set< /* Installed IDE name */ String>>{};
      for (final MapEntry(key: ide, value: packages)
          in filteredSkills.entries) {
        for (final entry in packages.values) {
          for (final skill in entry.skills) {
            installedSkillsAndIdes.putIfAbsent(skill.name, () => {}).add(ide);
          }
        }
      }

      final sortedSkills = installedSkillsAndIdes.keys.toList()..sort();
      for (final skillName in sortedSkills) {
        final idesStr = installedSkillsAndIdes[skillName]!.join(', ');
        logger.info('  $skillName (installed in: $idesStr)');
      }
      logger.info('Rerun with `--skill <name>`, or `--all` to remove skills.');
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
        skillNames: skillsToRemove,
        // Don't worry about local modifications for the remove command
        force: true,
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

    logger.info('Removed $totalRemoved skill(s)');
  }
}
