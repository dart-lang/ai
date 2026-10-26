import 'dart:io';

import 'package:logging/logging.dart';

import '../core/skill_scanner.dart';

import 'agent.dart';

/// Abstract interface for agent-specific skill installation and removal.
abstract class AgentAdapter {
  final Agent agent;

  AgentAdapter(this.agent);

  /// Installs a skill from the scanned location into the agent's directory.
  ///
  /// Returns the skill name as installed and its content hash (if any).
  Future<InstallSkillResult> installSkill(ScannedSkill skill);

  /// A logger for this agent Adapter. Should contain the name of the agent.
  Logger get logger;

  /// Removes a previously installed skill by its name.
  ///
  /// Returns `true` if removed successfully or it didn't exist.
  /// Returns `false` if the removal failed.
  Future<bool> removeSkill(String skillName);

  /// Returns the absolute path to the agent's skills/rules directory.
  String get skillsDirectory;

  /// Creates the skills directory if it doesn't exist.
  Future<void> ensureSkillsDirectory();

  /// Returns the current hash of an installed [skill] as currently installed.
  ///
  /// Returns `null` if it cannot be computed (typically due to the directory
  /// not existing).
  Future<String?> computeInstalledSkillHash(String skill);

  /// Returns the current hash of a skill located at [skillDir], as it would be
  /// if installed by this package.
  ///
  /// Returns `null` if it cannot be computed (typically due to the directory
  /// not existing).
  Future<String?> computeSourceSkillHash(Directory skillDir);
}

/// The result type for [AgentAdapter.installSkill].
typedef InstallSkillResult = ({String name, String contentHash});
