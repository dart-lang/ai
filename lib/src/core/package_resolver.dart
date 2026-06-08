import 'dart:io';

import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;

import 'workspace_resolver.dart';

/// Information about a resolved Dart package on disk.
class ResolvedPackage {
  final String name;
  final String rootPath;

  /// The path to the package config that resolved this package.
  final String originalPackageConfigPath;

  const ResolvedPackage(
      {required this.name,
      required this.rootPath,
      required this.originalPackageConfigPath});
}

/// Resolves Dart package dependency locations from package_config.json.
///
/// Two APIs are provided:
/// - **Instance API**: Use `PackageResolver(projectPath)` for a single project.
///   Methods: [resolve], [hasPackageConfig], [packageConfigPath].
/// - **Static API**: Use [resolveWorkspace] for a workspace (monorepo). Use when
///   you have a [WorkspaceLayout].
class PackageResolver {
  final String projectPath;

  const PackageResolver(this.projectPath);

  /// Resolves all dependency packages to their on-disk locations.
  ///
  /// If [packageName] is provided, only that package is returned.
  /// Returns an empty list if the package is not found.
  Future<List<ResolvedPackage>> resolve({String? packageName}) async {
    final configPath = await findPackageConfigPath(Directory(projectPath));
    if (configPath == null) {
      throw StateError(
        'No package_config.json found. Run "dart pub get" first.',
      );
    }
    final config = PackageConfig.parseString(
        await File(configPath).readAsString(), Uri.file(configPath));

    final packages = <ResolvedPackage>[];
    for (final package in config.packages) {
      if (packageName != null && package.name != packageName) continue;

      final rootUri = package.root;
      if (rootUri.scheme != 'file') continue;

      final rootPath = rootUri.toFilePath();

      packages.add(ResolvedPackage(
          name: package.name,
          rootPath: rootPath,
          originalPackageConfigPath: configPath));
    }

    return packages;
  }

  /// Resolves external dependencies across all packages in a [workspace].
  ///
  /// Reads each unique `package_config.json`, merges the results, and filters
  /// out workspace member packages (those are the user's own code, not
  /// external dependencies that might ship skills).
  ///
  /// If [packageNames] is non-empty, only those packages are returned.
  static Future<List<ResolvedPackage>> resolveWorkspace(
    WorkspaceLayout workspace, {
    Set<String> packageNames = const {},
  }) async {
    final memberNames = workspace.packages.map((p) => p.name).toSet();

    // Deduplicate by config path -- pub workspaces share one config.
    final configPaths =
        workspace.packages.map((p) => p.packageConfigPath).toSet();

    final seenPaths = <String>{};
    final results = <ResolvedPackage>[];

    for (final configPath in configPaths) {
      final configFile = File(configPath);
      if (!configFile.existsSync()) continue;

      final config = await loadPackageConfig(configFile);
      for (final package in config.packages) {
        if (memberNames.contains(package.name)) continue;

        if (packageNames.isNotEmpty && !packageNames.contains(package.name)) {
          continue;
        }

        final rootUri = package.root;
        if (rootUri.scheme != 'file') continue;

        final rootPath = rootUri.toFilePath();
        if (!seenPaths.add(rootPath)) continue;

        results.add(
          ResolvedPackage(
              name: package.name,
              rootPath: rootPath,
              originalPackageConfigPath: configPath),
        );
      }
    }

    return results;
  }

  static Future<String?> findPackageConfigPath(Directory dir) async {
    while (dir.path != dir.parent.path) {
      final configFile =
          File(p.join(dir.path, '.dart_tool', 'package_config.json'));
      if (await configFile.exists()) return configFile.path;
      dir = dir.parent;
    }
    return null;
  }
}
