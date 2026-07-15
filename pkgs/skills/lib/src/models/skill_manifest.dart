import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/git_repos.dart';

/// Tracks which skills are installed, per agent and per package.
class SkillManifest {
  static const int currentVersion = 2;
  static final String cacheDirPath = p.join('.dart_tool', 'skills');
  static final String configDirPath = p.join('.config', 'dart_skills');
  static const String configName = 'skills_config.json';

  /// Returns the platform-correct path to the manifest file under [rootPath].
  static String pathIn(String rootPath) =>
      p.join(rootPath, configDirPath, configName);

  /// Deletes cache files under [rootPath] if they exist, as well as config
  /// files and directories if they are empty.
  static Future<void> cleanup(String rootPath) async {
    final cacheDir = Directory(p.join(rootPath, cacheDirPath));
    if (await cacheDir.exists()) await cacheDir.delete(recursive: true);

    final manifest = await loadFromRoot(rootPath);
    if (manifest != null && manifest.isEmpty) {
      await File(p.join(rootPath, configDirPath, configName)).delete();
    }

    final configDir = Directory(p.join(rootPath, configDirPath));
    if (await configDir.exists() && await configDir.list().isEmpty) {
      await configDir.delete();
    }
  }

  /// The version of the manifest when it was loaded.
  final int version;

  /// Outer key: agent name, inner key: package uri or git uri.
  final Map<String, Map<String, SkillsEntry>> installations;

  /// Configured git repos for this workspace.
  const SkillManifest({
    this.version = currentVersion,
    this.installations = const {},
  });

  /// Migrates existing state from `.dart_skills` to `.dart_tool/skills`.
  static Future<void> migrateIfNeeded(String rootPath) async {
    final oldDir = Directory(p.join(rootPath, '.dart_skills'));
    final newCacheDir = Directory(p.join(rootPath, cacheDirPath));
    final newConfigDir = Directory(p.join(rootPath, configDirPath));
    final oldManifestFile = File(
      p.join(newCacheDir.path, SkillManifest.configName),
    );

    if (await oldDir.exists()) {
      if (!await newCacheDir.exists()) {
        await newCacheDir.parent.create(recursive: true);
        await oldDir.rename(newCacheDir.path);
        if (await oldManifestFile.exists()) {
          if (!await newConfigDir.exists()) {
            await newConfigDir.create(recursive: true);
          }
          await oldManifestFile.rename(SkillManifest.pathIn(rootPath));
        }
      }
    }
  }

  /// Loads the manifest from [file], or returns null if it doesn't exist.
  static Future<SkillManifest?> load(File file) async {
    if (!await file.exists()) return null;
    final content = await file.readAsString();
    if (content.trim().isEmpty) return null;
    final json = jsonDecode(content) as Map<String, dynamic>;
    return SkillManifest.fromJson(json);
  }

  /// Loads the manifest from [file], or returns an empty manifest if none exists.
  static Future<SkillManifest> loadOrEmpty(File file) async {
    final loaded = await load(file);
    return loaded ?? const SkillManifest();
  }

  /// Loads the manifest for [rootPath], performing migration if needed.
  ///
  /// Returns null if the manifest does not exist.
  static Future<SkillManifest?> loadFromRoot(String rootPath) async {
    await migrateIfNeeded(rootPath);
    return load(File(pathIn(rootPath)));
  }

  /// Loads the manifest for [rootPath], performing migration if needed.
  ///
  /// Returns an empty manifest if none exists.
  static Future<SkillManifest> loadOrEmptyFromRoot(String rootPath) async {
    final loaded = await loadFromRoot(rootPath);
    return loaded ?? const SkillManifest();
  }

  factory SkillManifest.fromJson(Map<String, dynamic> json) {
    final version = json['version'] as int? ?? 1;
    final installationsJson =
        json['installations'] as Map<String, dynamic>? ?? {};
    final installations = installationsJson.map((agentKey, agentValue) {
      final pkgsJson = agentValue as Map<String, dynamic>;
      final pkgs = pkgsJson.map(
        (pkgKey, pkgValue) => MapEntry(
          pkgKey,
          SkillsEntry.fromJson(pkgValue as Map<String, dynamic>),
        ),
      );
      return MapEntry(agentKey, pkgs);
    });

    return SkillManifest(version: version, installations: installations);
  }

  Map<String, dynamic> toJson() {
    return {
      'version': currentVersion,
      'installations': installations.map(
        (agent, entries) => MapEntry(
          agent,
          entries.map((uri, entry) => MapEntry(uri, entry.toJson())),
        ),
      ),
    };
  }

  /// Saves the manifest to [file], creating parent directories if needed.
  Future<void> save(File file) async {
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString('${encoder.convert(toJson())}\n');
  }

  /// All agent names with at least one installed skill.
  Iterable<String> get allAgents => installations.keys;

  /// Returns the packages map for a given [agent], or empty if none.
  Map<String, SkillsEntry> sourceUrisForAgent(String agent) =>
      installations[agent] ?? {};

  /// Dynamically infers all git repositories currently installed by scanning
  /// source URIs for all non-package: URIs.
  List<GitRepo> get gitRepos {
    final uris = <String>{};
    for (final agent in installations.values) {
      for (final uri in agent.keys) {
        if (!uri.startsWith('package:')) {
          uris.add(uri);
        }
      }
    }
    return uris.map((uri) => GitRepo(cloneUrl: uri)).toList();
  }

  /// All installed skill entries for a given [agent].
  ///
  /// If [packageNames] is given and non-empty, only skills from those packages
  /// will be returned.
  Iterable<InstalledSkillEntry> allSkillsForAgent(String agent) sync* {
    for (final entry in sourceUrisForAgent(agent).values) {
      yield* entry.skills;
    }
  }

  /// All installed skill entries across all agents.
  Iterable<InstalledSkillEntry> get allSkills sync* {
    for (final agent in installations.keys) {
      yield* allSkillsForAgent(agent);
    }
  }

  /// Whether there are any installations at all.
  bool get isEmpty =>
      installations.isEmpty ||
      installations.values.every((pkgs) => pkgs.isEmpty);

  /// Returns a copy with [entry] set for [agent] + [sourceUri].
  SkillManifest withSourceUri(
    String agent,
    String sourceUri,
    SkillsEntry entry,
  ) {
    final updated = _deepCopy();
    updated.putIfAbsent(agent, () => {})[sourceUri] = entry;
    return SkillManifest(version: version, installations: updated);
  }

  /// Returns a copy with [sourceUri] removed from [agent].
  SkillManifest withoutSourceUri(String agent, String sourceUri) {
    final updated = _deepCopy();
    updated[agent]?.remove(sourceUri);
    if (updated[agent]?.isEmpty ?? false) updated.remove(agent);
    return SkillManifest(version: version, installations: updated);
  }

  /// Returns a copy with all packages removed for [agent].
  SkillManifest withoutAgent(String agent) {
    final updated = _deepCopy();
    updated.remove(agent);
    return SkillManifest(version: version, installations: updated);
  }

  Map<String, Map<String, SkillsEntry>> _deepCopy() {
    return installations.map(
      (agent, pkgs) => MapEntry(agent, Map<String, SkillsEntry>.from(pkgs)),
    );
  }
}

/// Skills installed from a single package or git source.
class SkillsEntry {
  final List<InstalledSkillEntry> skills;

  const SkillsEntry({this.skills = const []});

  factory SkillsEntry.fromJson(Map<String, dynamic> json) {
    final skillsList = json['skills'] as List<dynamic>? ?? [];
    return SkillsEntry(
      skills: skillsList
          .map((s) => InstalledSkillEntry.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'skills': skills.map((s) => s.toJson()).toList()};
  }
}

class InstalledSkillEntry {
  final String name;
  final DateTime installedAt;
  final String? contentHash;
  final bool isInstalled;

  const InstalledSkillEntry({
    required this.name,
    required this.installedAt,
    this.contentHash,
    this.isInstalled = true,
  });

  factory InstalledSkillEntry.fromJson(Map<String, dynamic> json) {
    return InstalledSkillEntry(
      name: json['name'] as String,
      installedAt: DateTime.parse(json['installedAt'] as String),
      contentHash: json['contentHash'] as String?,
      isInstalled: json['isInstalled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'installedAt': installedAt.toUtc().toIso8601String(),
      if (contentHash != null) 'contentHash': contentHash,
      if (!isInstalled) 'isInstalled': false,
    };
  }
}
