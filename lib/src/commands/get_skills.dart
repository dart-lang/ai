import 'dart:io';
import 'dart:io' as io; // to distinguish stdout from io.stdout, etc.

import 'package:args/command_runner.dart';
import 'package:skills/src/commands/skills_command.dart';
import 'package:skills/src/core/git_runner.dart';
import 'package:skills/src/core/package_resolver.dart';
import 'package:skills/src/core/pub_runner.dart';
import 'package:skills/src/core/registry_scanner.dart';
import 'package:skills/src/core/registry_sync.dart';
import 'package:skills/src/core/skill_installer.dart';
import 'package:skills/src/core/skill_merger.dart';
import 'package:skills/src/core/skill_scanner.dart';
import 'package:skills/src/core/workspace_resolver.dart';
import 'package:skills/src/ide/ide.dart';

/// Installs skills from package dependencies for [ides].
Future<bool> getSkills({
  required List<Ide> ides,
  required WorkspaceLayout workspace,
  GitRunner gitRunner = const GitRunner(),
  String usage = '',
  String? packageName,
  IOSink? stdout,
  IOSink? stderr,
}) async {
  stdout ??= io.stdout;
  stderr ??= io.stderr;

  final ready = await PubRunner.ensureWorkspaceConfigs(workspace);
  if (!ready) {
    throw UsageException('Failed to run pub get.', usage);
  }

  final packages = await PackageResolver.resolveWorkspace(
    workspace,
    packageName: packageName,
  );

  if (packageName != null && packages.isEmpty) {
    stderr.writeln('Package "$packageName" not found in dependencies.');
    return false;
  }

  const scanner = SkillScanner();
  final dartSkills = await scanner.scan(packages);
  final rootPath = workspace.rootPath;

  var registrySkills = <ScannedSkill>[];
  if (await gitRunner.isAvailable) {
    const registrySync = RegistrySync();
    await registrySync.sync(rootPath, onProgress: stdout.writeln);
    const registryScanner = RegistryScanner();
    registrySkills = await registryScanner.scan(rootPath);
  } else {
    stderr.writeln(
      'Warning: git not found. Skipping GitHub registry skills.',
    );
  }

  final resolvedPackageNames = packages.map((p) => p.name).toSet();
  final skills = mergeSkills(
    dartSkills: dartSkills,
    registrySkills: registrySkills,
    resolvedPackageNames: resolvedPackageNames,
  );

  if (skills.isEmpty) {
    stdout.writeln('No skills found in ${packageName ?? "any"} packages.');
    return false;
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
      stdout.writeln('  [${info.ideName}] Installed ${info.skillName}');
    }
  }

  await manifest.save(manifestFile(rootPath));

  final ideNames = ides.map((e) => e.cliName).join(', ');
  stdout.writeln('Installed ${skills.length} skill(s) for $ideNames.');

  return true;
}
