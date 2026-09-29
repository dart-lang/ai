import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../core/workspace_resolver.dart';
import '../models/skill_manifest.dart';

/// Base class for skills CLI commands with shared workspace and manifest helpers.
abstract class SkillsCommand extends Command<void> {
  late final logger = Logger('skills $name');

  /// Resolves the workspace layout.
  ///
  /// Uses [--directory] if set, otherwise the current working directory.
  /// This allows tests and scripts to run without changing the process cwd.
  ///
  /// If [allowNoPackages] is `true`, a directory that contains no Dart
  /// packages resolves to an empty workspace rather than throwing.
  Future<WorkspaceLayout> resolveWorkspace({
    bool allowNoPackages = false,
  }) async {
    final dir = globalResults?['directory'] as String?;
    final path = dir != null
        ? p.normalize(p.absolute(dir))
        : Directory.current.path;
    return const WorkspaceResolver().resolve(
      path,
      allowNoPackages: allowNoPackages,
    );
  }
}

/// Returns the manifest file for the given [rootPath].
File manifestFile(String rootPath) {
  return File(SkillManifest.pathIn(rootPath));
}
