import 'package:args/command_runner.dart';

import '../core/package_resolver.dart';
import '../core/pub_runner.dart';
import '../core/skill_installer.dart';
import '../agent/agent.dart';
import '../models/skill_manifest.dart';
import 'options.dart';
import 'skills_command.dart';
import 'package:skills/src/core/dialog_support.dart';

/// Removes installed skills whose package is no longer in the dependency tree.
class PruneCommand extends SkillsCommand {
  @override
  final String name = 'prune';

  @override
  final String description =
      'Remove skills whose package is no longer in the dependency tree.';

  final DialogSupport? _dialogSupport;

  PruneCommand({DialogSupport? dialogSupport})
    : _dialogSupport = dialogSupport {
    addAgentOption(argParser);
  }

  @override
  Future<void> run() async {
    final argResults = this.argResults!;
    final workspace = await resolveWorkspace();
    final rootPath = workspace.rootPath;

    final ready = await PubRunner.ensureWorkspaceConfigs(workspace);
    if (!ready) {
      throw UsageException('Failed to run pub get.', usage);
    }

    final packages = await PackageResolver.resolveWorkspace(workspace);
    final referencedNames = packages.map((p) => p.name).toSet();

    final loaded = await SkillManifest.loadOrEmptyFromRoot(rootPath);

    if (loaded.isEmpty) {
      logger.info('No managed skills found.');
      return;
    }

    var manifest = loaded;

    final List<Agent> targetIdes;
    final parsedAgents = parseAgentOption(argResults);
    if (parsedAgents.isNotEmpty) {
      targetIdes = parsedAgents;
    } else {
      targetIdes = manifest.allAgents
          .map((name) => Agent.fromCliName(name))
          .whereType<Agent>()
          .toList();
    }

    final installer = SkillInstaller(_dialogSupport);
    var totalRemoved = 0;
    final prunedPackages = <String>{};

    for (final agent in targetIdes) {
      final pkgs = manifest.sourceUrisForAgent(agent.cliName);
      final pkgsToPrune = pkgs.keys
          .where(
            (uri) =>
                uri.startsWith('package:') &&
                !referencedNames.contains(uri.substring('package:'.length)),
          )
          .toSet();
      prunedPackages.addAll(pkgsToPrune);
      if (pkgsToPrune.isEmpty) continue;

      final result = await installer.removeSkillsForIde(
        agent: agent,
        rootPath: rootPath,
        manifest: manifest,
        sourceUris: pkgsToPrune,
      );
      manifest = result.manifest;
      totalRemoved += result.removedCount;
      for (final info in result.removed) {
        logger.info('  [${info.agentName}] Removed ${info.skillName}');
      }
    }

    await manifest.save(manifestFile(rootPath));
    if (manifest.isEmpty) {
      await SkillManifest.cleanup(rootPath);
    }

    if (totalRemoved == 0) {
      logger.info('No skills to prune.');
    } else {
      logger.info(
        'Pruned $totalRemoved skill(s) from ${prunedPackages.length} package(s).',
      );
    }
  }
}
