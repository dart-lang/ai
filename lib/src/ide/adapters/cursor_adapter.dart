import 'package:logging/logging.dart';

import '../ide.dart';
import 'agent_skills_adapter.dart';

/// Cursor IDE adapter.
///
/// Installs skills to `.cursor/skills/<pkg>-<skill>/SKILL.md`.
class CursorAdapter extends AgentSkillsAdapter {
  @override
  final Logger logger = Logger('CursorAdapter');

  CursorAdapter(String projectPath, {super.dialogSupport})
    : super(Ide.cursor.skillsPath(projectPath));
}
