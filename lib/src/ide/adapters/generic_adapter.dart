import '../ide.dart';
import 'agent_skills_adapter.dart';

/// Generic agent IDE adapter for Antigravity, Codex, or generic.
///
/// Installs skills to `.agent/skills/<pkg>-<skill>/SKILL.md`.
class GenericAdapter extends AgentSkillsAdapter {
  GenericAdapter(String projectPath)
      : super(Ide.generic.skillsPath(projectPath));
}
