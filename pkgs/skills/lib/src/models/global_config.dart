import 'dart:convert';
import 'dart:io';

import 'package:cli_util/cli_util.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../core/git_repos.dart';

/// Global configuration for skill git repos.
class GlobalConfig {
  static const String baseName = 'global_config.json';

  /// For testing purposes to override the global path.
  @visibleForTesting
  static String? globalPathOverride;

  /// Returns the platform-correct path to the global config file.
  static String get globalPath {
    if (globalPathOverride != null) return globalPathOverride!;
    final configDir = BaseDirectories('dart_skills').configHome;
    return p.join(configDir, baseName);
  }

  final List<GitRepo> gitRepos;

  const GlobalConfig({this.gitRepos = const []});

  factory GlobalConfig.fromJson(Map<String, dynamic> json) {
    // Fallback to 'registries' for backwards compatibility
    final reposJson =
        (json['gitRepos'] ?? json['registries']) as List<dynamic>? ?? [];
    final gitRepos = reposJson
        .map((r) => GitRepo.fromJson(r as Map<String, dynamic>))
        .toList();

    return GlobalConfig(gitRepos: gitRepos);
  }

  Map<String, dynamic> toJson() {
    return {'gitRepos': gitRepos.map((r) => r.toJson()).toList()};
  }

  /// Loads the config from [file], or returns null if it doesn't exist.
  static Future<GlobalConfig?> load(File file) async {
    if (!await file.exists()) return null;
    final content = await file.readAsString();
    if (content.trim().isEmpty) return null;
    final json = jsonDecode(content) as Map<String, dynamic>;
    return GlobalConfig.fromJson(json);
  }

  /// Loads the config from [file], or returns an empty config if none exists.
  static Future<GlobalConfig> loadOrEmpty(File file) async {
    final loaded = await load(file);
    return loaded ?? const GlobalConfig();
  }

  /// Saves the config to [file], creating parent directories if needed.
  Future<void> save(File file) async {
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString('${encoder.convert(toJson())}\n');
  }

  /// Returns a copy with [repo] added.
  GlobalConfig withGitRepo(GitRepo repo) {
    if (gitRepos.any((r) => r.cloneUrl == repo.cloneUrl)) return this;
    return GlobalConfig(gitRepos: [...gitRepos, repo]);
  }

  /// Returns a copy with [repo] removed.
  GlobalConfig withoutGitRepo(GitRepo repo) {
    return GlobalConfig(
      gitRepos: gitRepos.where((r) => r.cloneUrl != repo.cloneUrl).toList(),
    );
  }
}
