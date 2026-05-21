import 'package:path/path.dart' as p;

import '../models/skill_manifest.dart';

/// How skill directories are organized inside a registry repo's `skills/` folder.
enum RegistrySkillLayout {
  /// Skills are directly under `skills/`; each dir name is `<package>-<suffix>`
  /// (e.g. `skills/shadcn_ui-buttons`).
  flat,

  /// Skills are grouped by package: `skills/<package>/<skill-dir>/`
  /// (e.g. `skills/riverpod/riverpod-get-started`).
  groupedByPackage,
}

/// A GitHub registry repository with owner, name, and skill directory layout.
class RegistryRepo {
  final String owner;
  final String name;

  /// How skills are laid out under this repo's `skills/` directory.
  final RegistrySkillLayout skillLayout;

  /// If set, used instead of the default GitHub URL (for testing with local repos).
  final String? customCloneUrl;

  const RegistryRepo({
    required this.owner,
    required this.name,
    required this.skillLayout,
    this.customCloneUrl,
  });

  /// The path segment for this repo under [reposDir], e.g. "flutter/skills".
  String get pathSegment => p.join(owner, name);

  /// Full clone URL.
  String get cloneUrl =>
      customCloneUrl ?? 'https://github.com/$owner/$name.git';
}

/// Returns the absolute path to the repos root under [rootPath]:
/// `<rootPath>/.dart_tool/skills/repos`.
String registryReposPath(String rootPath) {
  return p.join(rootPath, SkillManifest.dirName, 'repos');
}

/// Returns the absolute path where [repo] should be cloned under [rootPath]:
/// `<rootPath>/.dart_tool/skills/repos/<owner>/<name>`.
String registryRepoPath(String rootPath, RegistryRepo repo) {
  return p.join(registryReposPath(rootPath), repo.pathSegment);
}
