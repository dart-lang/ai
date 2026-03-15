import 'dart:io';

import 'package:args/command_runner.dart';

import '../core/package_resolver.dart';
import '../core/pub_runner.dart';
import '../core/skill_installer.dart';
import '../ide/ide.dart';
import '../models/skill_manifest.dart';
import 'options.dart';
import 'skills_command.dart';

/// Removes installed skills whose package is no longer in the dependency tree.
class PruneCommand extends SkillsCommand {
  @override
  final String name = 'prune';

  @override
  final String description =
      'Remove skills whose package is no longer in the dependency tree.';

  PruneCommand() {
    addIdeOption(argParser);
  }

  @override
  Future<void> run() async {
    final workspace = await resolveWorkspace();
    final rootPath = workspace.rootPath;

    final ready = await PubRunner.ensureWorkspaceConfigs(workspace);
    if (!ready) {
      throw UsageException('Failed to run pub get.', usage);
    }

    final packages = await PackageResolver.resolveWorkspace(workspace);
    final referencedNames = packages.map((p) => p.name).toSet();

    final loaded = await SkillManifest.load(manifestFile(rootPath));

    if (loaded == null || loaded.isEmpty) {
      stdout.writeln('No managed skills found.');
      return;
    }

    var manifest = loaded;

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
    final prunedPackages = <String>{};

    for (final ide in targetIdes) {
      final pkgs = manifest.packagesForIde(ide.cliName);
      for (final packageName in pkgs.keys) {
        if (referencedNames.contains(packageName)) continue;

        final result = await installer.removeSkillsForIde(
          ide: ide,
          rootPath: rootPath,
          manifest: manifest,
          packageName: packageName,
        );
        manifest = result.manifest;
        totalRemoved += result.removedCount;
        prunedPackages.add(packageName);
        for (final info in result.removed) {
          stdout.writeln('  [${info.ideName}] Removed ${info.skillName}');
        }
      }
    }

    if (manifest.isEmpty) {
      await SkillManifest.cleanupDir(rootPath);
    } else {
      await manifest.save(manifestFile(rootPath));
    }

    if (totalRemoved == 0) {
      stdout.writeln('No skills to prune.');
    } else {
      stdout.writeln(
        'Pruned $totalRemoved skill(s) from ${prunedPackages.length} package(s).',
      );
    }
  }
}
