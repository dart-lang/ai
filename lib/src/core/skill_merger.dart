import 'skill_scanner.dart';

/// Merges Dart-package skills with registry skills, applying dependency filter
/// and Dart precedence per package.
///
/// - Only registry skills whose [ScannedSkill.packageName] is in
///   [resolvedPackageNames] are included.
/// - If a package has any Dart skills, registry skills for that package are
///   excluded (Dart wins).
List<ScannedSkill> mergeSkills({
  required List<ScannedSkill> dartSkills,
  required List<ScannedSkill> registrySkills,
  required Set<String> resolvedPackageNames,
}) {
  final packagesWithDartSkills = dartSkills.map((s) => s.packageName).toSet();
  final filteredRegistry = registrySkills.where((s) {
    if (!resolvedPackageNames.contains(s.packageName)) return false;
    if (packagesWithDartSkills.contains(s.packageName)) return false;
    return true;
  });
  return [...dartSkills, ...filteredRegistry];
}
