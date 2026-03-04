import 'dart:io';

import '../core/skill_installer.dart';
import '../ide/ide.dart';
import '../models/skill_manifest.dart';
import 'options.dart';
import 'skills_command.dart';

/// Removes managed skills.
class RemoveCommand extends SkillsCommand {
  @override
  final String name = 'remove';

  @override
  final String description = 'Remove managed skills.';

  RemoveCommand() {
    addIdeOption(argParser);
  }

  @override
  Future<void> run() async {
    final workspace = await resolveWorkspace();
    final rootPath = workspace.rootPath;

    final loaded = await SkillManifest.load(manifestFile(rootPath));

    if (loaded == null || loaded.isEmpty) {
      stdout.writeln('No managed skills found.');
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

    const installer = SkillInstaller();
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
        stdout.writeln('  [${info.ideName}] Removed ${info.skillName}');
      }
    }

    await manifest.save(manifestFile(rootPath));

    if (packageName != null) {
      stdout.writeln('Removed skills from $packageName.');
    } else {
      stdout.writeln('Removed $totalRemoved managed skill(s).');
    }
  }
}
