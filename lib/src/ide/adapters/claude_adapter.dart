import '../ide.dart';
import 'agent_skills_adapter.dart';

/// Claude Code adapter.
///
/// Installs skills to `.claude/skills/<skill-name>/` per
/// [Claude Code skills](https://code.claude.com/docs/en/skills).
class ClaudeAdapter extends AgentSkillsAdapter {
  ClaudeAdapter(String projectPath) : super(Ide.claude.skillsPath(projectPath));
}
