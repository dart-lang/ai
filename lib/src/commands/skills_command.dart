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
  Future<WorkspaceLayout> resolveWorkspace() async {
    final dir = globalResults?['directory'] as String?;
    final path =
        dir != null ? p.normalize(p.absolute(dir)) : Directory.current.path;
    return const WorkspaceResolver().resolve(path);
  }

  /// The package names from rest arguments, or null if not specified.
  List<String>? get packageNamesArg => switch (argResults?.rest) {
        List<String> rest when rest.isNotEmpty => rest,
        _ => null,
      };
}

/// Returns the manifest file for the given [rootPath].
File manifestFile(String rootPath) {
  return File(SkillManifest.pathIn(rootPath));
}
