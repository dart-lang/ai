import 'package:logging/logging.dart';

import '../agent.dart';
import 'agent_skills_adapter.dart';

/// Claude Code adapter.
///
/// Installs skills to `.claude/skills/<skill-name>/` per
/// [Claude Code skills](https://code.claude.com/docs/en/skills).
class ClaudeAdapter extends AgentSkillsAdapter {
  @override
  final Logger logger = Logger('ClaudeAdapter');

  ClaudeAdapter(String projectPath, {super.dialogSupport})
    : super(Agent.claude, Agent.claude.skillsPath(projectPath));
}
