import 'dart:convert';
import 'dart:io';

import 'package:cli_util/cli_util.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../core/registry_repos.dart';

/// Global configuration for skill registries.
class GlobalConfig {
  static const String baseName = 'global_config.json';

  /// For testing purposes to override the global path.
  @visibleForTesting
  static String? globalPathOverride;

  /// Returns the platform-correct path to the global registries file.
  static String get globalPath {
    if (globalPathOverride != null) return globalPathOverride!;
    final configDir = BaseDirectories('dart_skills').configHome;
    return p.join(configDir, baseName);
  }

  final List<RegistryRepo> registries;

  const GlobalConfig({
    this.registries = const [],
  });

  factory GlobalConfig.fromJson(Map<String, dynamic> json) {
    final registriesJson = json['registries'] as List<dynamic>? ?? [];
    final registries = registriesJson
        .map((r) => RegistryRepo.fromJson(r as Map<String, dynamic>))
        .toList();

    return GlobalConfig(registries: registries);
  }

  Map<String, dynamic> toJson() {
    return {
      'registries': registries.map((r) => r.toJson()).toList(),
    };
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
  GlobalConfig withRegistry(RegistryRepo repo) {
    return GlobalConfig(
      registries: [...registries, repo],
    );
  }

  /// Returns a copy with [repo] removed.
  GlobalConfig withoutRegistry(RegistryRepo repo) {
    return GlobalConfig(
      registries: registries.where((r) => r.cloneUrl != repo.cloneUrl).toList(),
    );
  }
}
