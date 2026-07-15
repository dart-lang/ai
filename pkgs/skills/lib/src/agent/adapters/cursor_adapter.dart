import 'package:logging/logging.dart';

import '../agent.dart';
import 'agent_skills_adapter.dart';

/// Cursor agent adapter.
///
/// Installs skills to `.cursor/skills/<pkg>-<skill>/SKILL.md`.
class CursorAdapter extends AgentSkillsAdapter {
  @override
  final Logger logger = Logger('CursorAdapter');

  CursorAdapter(String projectPath, {super.dialogSupport})
    : super(Agent.cursor, Agent.cursor.skillsPath(projectPath));
}
