import '../core/skill_scanner.dart';

/// Abstract interface for IDE-specific skill installation and removal.
abstract class IdeAdapter {
  /// Installs a skill from the scanned location into the IDE's directory.
  ///
  /// Returns the skill name as installed.
  Future<String> installSkill(ScannedSkill skill);

  /// Removes a previously installed skill by its name.
  Future<void> removeSkill(String skillName);

  /// Returns the absolute path to the IDE's skills/rules directory.
  String get skillsDirectory;

  /// Creates the skills directory if it doesn't exist.
  Future<void> ensureSkillsDirectory();
}
