import 'package:logging/logging.dart';

import '../core/dialog_support.dart';
import '../core/skill_scanner.dart';

/// Abstract interface for IDE-specific skill installation and removal.
abstract class IdeAdapter {
  /// Installs a skill from the scanned location into the IDE's directory.
  ///
  /// Returns the skill name as installed and its content hash (if any).
  Future<InstallSkillResult> installSkill(ScannedSkill skill);

  /// A logger for this IDE Adapter. Should contain the name of the IDE.
  Logger get logger;

  /// Removes a previously installed skill by its name.
  ///
  /// If [originalHash] is provided, then it will check the current hash of the
  /// directory and prompt the user if they want to overwrite it, if there have
  /// been any manual changes since it was installed. If we do not have dialog
  /// support then it will log a warning advertising the `--force` flag and
  /// return `false`.
  ///
  /// Returns `true` if removed successfully or it didn't exist.
  /// Returns `false` if the user aborted the removal.
  Future<bool> removeSkill(String skillName,
      {String? originalHash, bool force = false});

  /// Returns the absolute path to the IDE's skills/rules directory.
  String get skillsDirectory;

  /// Creates the skills directory if it doesn't exist.
  Future<void> ensureSkillsDirectory();
}

/// The result type for [IdeAdapter.installSkill].
typedef InstallSkillResult = ({String name, String contentHash});

/// Helper method to prompt the user if they want to overwrite a skill that has
/// been modified locally since it was installed.
///
/// Returns `true` if the user approves it, [originalHash] was null, or the
/// hashes were equal.
Future<bool> promptOverwriteIfChanged({
  required DialogSupport? dialogSupport,
  required String skillName,
  required String? originalHash,
  required String currentHash,
  required Logger logger,
  bool force = false,
}) async {
  if (originalHash == null) return true;
  if (currentHash == originalHash) return true;
  if (force) return true;
  if (dialogSupport == null) {
    logger.warning(
        'Skipped upgrading $skillName due to local modifications. Re-run with '
        '`--force` to overwrite.');
    return false;
  }

  final result = await dialogSupport.showSingleSelectDialog(
    ['Yes', 'No'],
    title: 'Skill $skillName has local edits. Overwrite them?',
  );
  if (result == 0) return true;
  logger.warning('Skipped upgrading $skillName due to user selection');
  return false;
}
