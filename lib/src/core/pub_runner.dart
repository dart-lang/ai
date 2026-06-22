import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'workspace_resolver.dart';

/// Runs `pub get` for Dart/Flutter projects.
///
/// Two APIs are provided:
/// - **Instance API**: Use `PubRunner(projectPath)` for a single project.
///   Method: [runPubGet].
/// - **Static API**: Use [ensureWorkspaceConfigs] for a workspace. Ensures all
///   packages in a [WorkspaceLayout] have package_config.json.
class PubRunner {
  final String projectPath;

  const PubRunner(this.projectPath);

  static final logger = Logger('PubRunner');

  /// Detects whether the project uses Flutter (has flutter SDK dependency).
  bool get isFlutterProject {
    final pubspecFile = File(p.join(projectPath, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) return false;

    final content = pubspecFile.readAsStringSync();
    final yaml = loadYaml(content);
    if (yaml is! YamlMap) return false;

    final deps = yaml['dependencies'];
    if (deps is YamlMap && deps.containsKey('flutter')) return true;

    return false;
  }

  /// Runs `pub get` and returns the exit code.
  Future<int> runPubGet() async {
    final String executable;
    final List<String> args;

    if (isFlutterProject) {
      executable = 'flutter';
      args = ['pub', 'get'];
    } else {
      executable = 'dart';
      args = ['pub', 'get'];
    }

    logger.info('Running $executable ${args.join(' ')}...');

    final result = await Process.run(
      executable,
      args,
      workingDirectory: projectPath,
    );

    if (result.exitCode != 0) {
      logger.warning('$executable pub get failed:');
      logger.warning(result.stderr);
    }

    return result.exitCode;
  }

  /// Ensures all package_config.json files exist for a [workspace].
  ///
  /// For Dart pub workspaces, a single `pub get` at the root suffices.
  /// For melos or multi-package setups, runs `pub get` per member as needed.
  static Future<bool> ensureWorkspaceConfigs(WorkspaceLayout workspace) async {
    final configPaths = workspace.packages
        .map((p) => p.packageConfigPath)
        .toSet();

    for (final configPath in configPaths) {
      if (File(configPath).existsSync()) continue;

      // Find the project directory that owns this config.
      // The config is at <project>/.dart_tool/package_config.json
      final projectDir = p.dirname(p.dirname(configPath));
      final runner = PubRunner(projectDir);
      final exitCode = await runner.runPubGet();
      if (exitCode != 0) return false;
    }

    return true;
  }
}
