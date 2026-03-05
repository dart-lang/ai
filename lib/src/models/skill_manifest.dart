import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Tracks which skills are installed, per IDE and per package.
class SkillManifest {
  static const int currentVersion = 1;
  static const String dirName = '.dart_skills';
  static const String baseName = 'skills_config.json';

  /// Returns the platform-correct path to the manifest file under [rootPath].
  static String pathIn(String rootPath) => p.join(rootPath, dirName, baseName);

  /// Deletes the [dirName] directory under [rootPath] if it exists.
  static Future<void> cleanupDir(String rootPath) async {
    final dir = Directory(p.join(rootPath, dirName));
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// Outer key: IDE name, inner key: package name.
  final Map<String, Map<String, PackageSkillsEntry>> installations;

  const SkillManifest({this.installations = const {}});

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

  factory SkillManifest.fromJson(Map<String, dynamic> json) {
    final installationsJson =
        json['installations'] as Map<String, dynamic>? ?? {};
    final installations = installationsJson.map((ideKey, ideValue) {
      final pkgsJson = ideValue as Map<String, dynamic>;
      final pkgs = pkgsJson.map(
        (pkgKey, pkgValue) => MapEntry(
          pkgKey,
          PackageSkillsEntry.fromJson(pkgValue as Map<String, dynamic>),
        ),
      );
      return MapEntry(ideKey, pkgs);
    });

    return SkillManifest(installations: installations);
  }

  Map<String, dynamic> toJson() {
    return {
      'version': currentVersion,
      'installations': installations.map(
        (ideKey, pkgs) => MapEntry(
          ideKey,
          pkgs.map((pkgKey, entry) => MapEntry(pkgKey, entry.toJson())),
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

  /// All IDE names with at least one installed skill.
  Iterable<String> get allIdes => installations.keys;

  /// Returns the packages map for a given [ide], or empty if none.
  Map<String, PackageSkillsEntry> packagesForIde(String ide) =>
      installations[ide] ?? {};

  /// All installed skill entries for a given [ide].
  Iterable<InstalledSkillEntry> allSkillsForIde(String ide) sync* {
    for (final entry in packagesForIde(ide).values) {
      yield* entry.skills;
    }
  }

  /// All installed skill entries across all IDEs.
  Iterable<InstalledSkillEntry> get allSkills sync* {
    for (final ide in installations.keys) {
      yield* allSkillsForIde(ide);
    }
  }

  /// Whether there are any installations at all.
  bool get isEmpty =>
      installations.isEmpty ||
      installations.values.every((pkgs) => pkgs.isEmpty);

  /// Returns a copy with [entry] set for [ide] + [packageName].
  SkillManifest withPackage(
    String ide,
    String packageName,
    PackageSkillsEntry entry,
  ) {
    final updated = _deepCopy();
    updated.putIfAbsent(ide, () => {});
    updated[ide]![packageName] = entry;
    return SkillManifest(installations: updated);
  }

  /// Returns a copy with [packageName] removed from [ide].
  SkillManifest withoutPackage(String ide, String packageName) {
    final updated = _deepCopy();
    updated[ide]?.remove(packageName);
    if (updated[ide]?.isEmpty ?? false) updated.remove(ide);
    return SkillManifest(installations: updated);
  }

  /// Returns a copy with all packages removed for [ide].
  SkillManifest withoutIde(String ide) {
    final updated = _deepCopy();
    updated.remove(ide);
    return SkillManifest(installations: updated);
  }

  Map<String, Map<String, PackageSkillsEntry>> _deepCopy() {
    return installations.map(
      (ide, pkgs) => MapEntry(ide, Map<String, PackageSkillsEntry>.from(pkgs)),
    );
  }
}

/// Skills installed from a single package.
class PackageSkillsEntry {
  final List<InstalledSkillEntry> skills;

  const PackageSkillsEntry({this.skills = const []});

  factory PackageSkillsEntry.fromJson(Map<String, dynamic> json) {
    final skillsList = json['skills'] as List<dynamic>? ?? [];
    return PackageSkillsEntry(
      skills: skillsList
          .map((s) => InstalledSkillEntry.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'skills': skills.map((s) => s.toJson()).toList()};
  }
}

/// A single installed skill.
class InstalledSkillEntry {
  final String name;
  final DateTime installedAt;

  const InstalledSkillEntry({required this.name, required this.installedAt});

  factory InstalledSkillEntry.fromJson(Map<String, dynamic> json) {
    return InstalledSkillEntry(
      name: json['name'] as String,
      installedAt: DateTime.parse(json['installedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {'name': name, 'installedAt': installedAt.toUtc().toIso8601String()};
  }
}
