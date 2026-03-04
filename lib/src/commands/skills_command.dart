import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../core/workspace_resolver.dart';
import '../models/skill_manifest.dart';

/// Base class for skills CLI commands with shared workspace and manifest helpers.
abstract class SkillsCommand extends Command<void> {
  SkillsCommand();

  /// Resolves the workspace layout for the current directory.
  Future<WorkspaceLayout> resolveWorkspace() async {
    return const WorkspaceResolver().resolve(Directory.current.path);
  }

  /// Returns the manifest file for the given [rootPath].
  File manifestFile(String rootPath) {
    return File(p.join(rootPath, SkillManifest.fileName));
  }

  /// Loads the manifest from [rootPath], or returns an empty manifest if none exists.
  Future<SkillManifest> loadManifest(String rootPath) async {
    return SkillManifest.loadOrEmpty(manifestFile(rootPath));
  }

  /// The package name from rest arguments, or null if not specified.
  String? get packageNameArg =>
      argResults != null && argResults!.rest.isNotEmpty
      ? argResults!.rest.first
      : null;
}
