import 'dart:io';

import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Describes the layout of a project -- either a single package or a monorepo
/// workspace containing multiple packages.
class WorkspaceLayout {
  /// The root path where skills should be installed (IDE dirs, manifest).
  final String rootPath;

  /// The packages whose dependencies should be scanned for skills.
  final List<WorkspacePackage> packages;

  const WorkspaceLayout({required this.rootPath, required this.packages});

  bool get isWorkspace => packages.length > 1;
}

/// A single package within a workspace (or the sole package in a project).
class WorkspacePackage {
  final String name;
  final String path;

  /// Path to the `.dart_tool/package_config.json` that covers this package.
  final String packageConfigPath;

  const WorkspacePackage({
    required this.name,
    required this.path,
    required this.packageConfigPath,
  });
}

/// Resolves the workspace layout for a project directory.
///
/// Supports four resolution strategies in priority order:
/// 1. Dart pub workspaces (`workspace:` field in root pubspec.yaml)
/// 2. Melos (`melos.yaml` or `melos:` in pubspec.yaml)
/// 3. Single-package project
/// 4. Implicit workspace (no root pubspec.yaml, but subdirectories have them)
class WorkspaceResolver {
  const WorkspaceResolver();

  /// Resolves the workspace layout for [projectPath].
  ///
  /// If [projectPath] contains a `pubspec.yaml`, resolves using standard
  /// strategies (pub workspace, melos, single package). Otherwise, scans
  /// immediate subdirectories for Dart packages.
  Future<WorkspaceLayout> resolve(String projectPath) async {
    final pubspecFile = File(p.join(projectPath, 'pubspec.yaml'));
    if (await pubspecFile.exists()) {
      return _resolveFromPubspec(projectPath);
    }

    final implicit = await _resolveImplicitWorkspace(projectPath);
    if (implicit != null) return implicit;

    throw StateError(
      'No pubspec.yaml found in $projectPath. '
      'Run this command from a Dart or Flutter project root.',
    );
  }

  /// Resolves a workspace from a directory that contains a pubspec.yaml.
  Future<WorkspaceLayout> _resolveFromPubspec(String rootPath) async {
    final pubspecContent = await File(
      p.join(rootPath, 'pubspec.yaml'),
    ).readAsString();
    final pubspec = loadYaml(pubspecContent);
    if (pubspec is! YamlMap) {
      throw StateError('Invalid pubspec.yaml in $rootPath.');
    }

    // 1. Dart pub workspace
    final workspaceField = pubspec['workspace'];
    if (workspaceField is YamlList) {
      return _resolvePubWorkspace(rootPath, pubspec, workspaceField);
    }

    // 2. Melos
    final melosLayout = await _resolveMelos(rootPath, pubspec);
    if (melosLayout != null) return melosLayout;

    // 3. Single-package fallback
    return _resolveSinglePackage(rootPath, pubspec);
  }

  /// Scans immediate subdirectories of [rootPath] for Dart packages.
  /// Returns a workspace layout if any are found, or `null` otherwise.
  Future<WorkspaceLayout?> _resolveImplicitWorkspace(String rootPath) async {
    final canonicalRoot = p.canonicalize(rootPath);
    final dir = Directory(canonicalRoot);
    if (!await dir.exists()) return null;

    final packages = <WorkspacePackage>[];
    await for (final entity in dir.list()) {
      if (entity is! Directory) continue;
      final name = await _readPubspecName(entity.path);
      if (name == null) continue;
      packages.add(
        WorkspacePackage(
          name: name,
          path: p.normalize(entity.path),
          packageConfigPath: p.join(
            entity.path,
            '.dart_tool',
            'package_config.json',
          ),
        ),
      );
    }

    if (packages.isEmpty) return null;

    packages.sort((a, b) => a.name.compareTo(b.name));
    return WorkspaceLayout(rootPath: canonicalRoot, packages: packages);
  }

  Future<WorkspaceLayout> _resolvePubWorkspace(
    String rootPath,
    YamlMap pubspec,
    YamlList workspaceEntries,
  ) async {
    final sharedConfigPath = p.join(
      rootPath,
      '.dart_tool',
      'package_config.json',
    );

    final memberPaths = await _expandGlobs(
      rootPath,
      workspaceEntries.cast<String>().toList(),
    );

    final packages = <WorkspacePackage>[];
    for (final memberPath in memberPaths) {
      final memberPubspec = await _readPubspecName(memberPath);
      if (memberPubspec == null) continue;
      packages.add(
        WorkspacePackage(
          name: memberPubspec,
          path: memberPath,
          packageConfigPath: sharedConfigPath,
        ),
      );
    }

    // Also include the root package itself if it has a meaningful name
    // (workspace roots often use `name: _` as a placeholder).
    final rootName = pubspec['name'] as String?;
    if (rootName != null && rootName != '_') {
      packages.insert(
        0,
        WorkspacePackage(
          name: rootName,
          path: rootPath,
          packageConfigPath: sharedConfigPath,
        ),
      );
    }

    return WorkspaceLayout(rootPath: rootPath, packages: packages);
  }

  Future<WorkspaceLayout?> _resolveMelos(
    String rootPath,
    YamlMap pubspec,
  ) async {
    // Check for standalone melos.yaml
    final melosFile = File(p.join(rootPath, 'melos.yaml'));
    YamlMap? melosConfig;
    if (await melosFile.exists()) {
      final content = await melosFile.readAsString();
      final parsed = loadYaml(content);
      if (parsed is YamlMap) melosConfig = parsed;
    }

    // Check for melos section in pubspec.yaml (Melos 7.3.0+)
    melosConfig ??=
        pubspec['melos'] is YamlMap ? pubspec['melos'] as YamlMap : null;

    if (melosConfig == null) return null;

    final packagesField = melosConfig['packages'];
    if (packagesField is! YamlList || packagesField.isEmpty) return null;

    final ignoreField = melosConfig['ignore'];
    final ignorePatterns = ignoreField is YamlList
        ? ignoreField.cast<String>().toList()
        : <String>[];

    final memberPaths = await _expandGlobs(
      rootPath,
      packagesField.cast<String>().toList(),
      ignore: ignorePatterns,
    );

    final packages = <WorkspacePackage>[];
    for (final memberPath in memberPaths) {
      final memberName = await _readPubspecName(memberPath);
      if (memberName == null) continue;
      packages.add(
        WorkspacePackage(
          name: memberName,
          path: memberPath,
          packageConfigPath: p.join(
            memberPath,
            '.dart_tool',
            'package_config.json',
          ),
        ),
      );
    }

    if (packages.isEmpty) return null;

    return WorkspaceLayout(rootPath: rootPath, packages: packages);
  }

  WorkspaceLayout _resolveSinglePackage(String projectPath, YamlMap pubspec) {
    final name = pubspec['name'] as String? ?? p.basename(projectPath);
    return WorkspaceLayout(
      rootPath: projectPath,
      packages: [
        WorkspacePackage(
          name: name,
          path: projectPath,
          packageConfigPath: p.join(
            projectPath,
            '.dart_tool',
            'package_config.json',
          ),
        ),
      ],
    );
  }

  /// Expands glob patterns relative to [rootPath] to find directories
  /// containing a `pubspec.yaml`.
  Future<List<String>> _expandGlobs(
    String rootPath,
    List<String> patterns, {
    List<String> ignore = const [],
  }) async {
    final results = <String>{};

    for (final pattern in patterns) {
      final glob = Glob(pattern);
      final entities = glob.listSync(root: rootPath);
      for (final entity in entities) {
        if (entity is! Directory) continue;
        final pubspec = File(p.join(entity.path, 'pubspec.yaml'));
        if (pubspec.existsSync()) {
          results.add(p.normalize(entity.path));
        }
      }
    }

    // Apply ignore patterns.
    if (ignore.isNotEmpty) {
      for (final pattern in ignore) {
        final glob = Glob(pattern);
        results.removeWhere((path) {
          final relative = p.relative(path, from: rootPath);
          return glob.matches(relative);
        });
      }
    }

    return results.toList()..sort();
  }

  /// Reads the `name` field from the pubspec.yaml in [packagePath].
  Future<String?> _readPubspecName(String packagePath) async {
    final pubspecFile = File(p.join(packagePath, 'pubspec.yaml'));
    if (!await pubspecFile.exists()) return null;
    final content = await pubspecFile.readAsString();
    final yaml = loadYaml(content);
    if (yaml is! YamlMap) return null;
    return yaml['name'] as String?;
  }
}
