import 'dart:io';

import 'package:args/command_runner.dart';

import '../core/package_resolver.dart';
import '../core/pub_runner.dart';
import '../core/skill_installer.dart';
import '../core/skill_scanner.dart';
import 'options.dart';
import 'skills_command.dart';

/// Installs skills from package dependencies.
class GetCommand extends SkillsCommand {
  @override
  final String name = 'get';

  @override
  final String description = 'Install skills from package dependencies.';

  GetCommand() {
    addIdeOption(argParser);
  }

  @override
  Future<void> run() async {
    final workspace = await resolveWorkspace();
    final rootPath = workspace.rootPath;

    if (workspace.isWorkspace) {
      stdout.writeln(
        'Detected workspace with ${workspace.packages.length} packages.',
      );
    }

    final ides = resolveIdes(argResults: argResults, projectPath: rootPath);

    final ready = await PubRunner.ensureWorkspaceConfigs(workspace);
    if (!ready) {
      throw UsageException('Failed to run pub get.', usage);
    }

    final packageName = packageNameArg;

    final packages = await PackageResolver.resolveWorkspace(
      workspace,
      packageName: packageName,
    );

    if (packageName != null && packages.isEmpty) {
      stderr.writeln('Package "$packageName" not found in dependencies.');
      return;
    }

    const scanner = SkillScanner();
    final skills = await scanner.scan(packages);

    if (skills.isEmpty) {
      stdout.writeln('No skills found in ${packageName ?? "any"} packages.');
      return;
    }

    const installer = SkillInstaller();
    var manifest = await loadManifest(rootPath);

    for (final ide in ides) {
      final result = await installer.installSkillsForIde(
        ide: ide,
        rootPath: rootPath,
        skills: skills,
        manifest: manifest,
      );
      manifest = result.manifest;
      for (final info in result.installed) {
        stdout.writeln(
          '  [${info.ideName}] Installed ${info.skillName} from ${info.packageName}',
        );
      }
    }

    await manifest.save(manifestFile(rootPath));

    final ideNames = ides.map((e) => e.cliName).join(', ');
    stdout.writeln('Installed ${skills.length} skill(s) for $ideNames.');
  }
}
