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

/// A registry repository with a clone URL.
class RegistryRepo {
  final String cloneUrl;

  /// Absolute paths where this repo is installed.
  final List<String> installs;

  const RegistryRepo({
    required this.cloneUrl,
    this.installs = const [],
  });

  RegistryRepo copyWith({
    String? cloneUrl,
    List<String>? installs,
  }) {
    return RegistryRepo(
      cloneUrl: cloneUrl ?? this.cloneUrl,
      installs: installs ?? this.installs,
    );
  }

  factory RegistryRepo.fromJson(Map<String, dynamic> json) {
    final installs = (json['installs'] as List<dynamic>?)?.cast<String>() ?? [];
    final cloneUrl = json['cloneUrl'] as String;
    return RegistryRepo(cloneUrl: cloneUrl, installs: installs);
  }

  Map<String, dynamic> toJson() {
    return {
      'cloneUrl': cloneUrl,
      'installs': installs,
    };
  }

  /// Returns a copy with a new install location added.
  RegistryRepo withInstall(String location) {
    if (installs.contains(location)) return this;
    return RegistryRepo(cloneUrl: cloneUrl, installs: [...installs, location]);
  }

  /// The path segment for this repo under [reposDir].
  String get pathSegment => Uri.encodeComponent(cloneUrl);
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
