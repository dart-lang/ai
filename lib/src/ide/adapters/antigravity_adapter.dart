import '../ide.dart';
import 'agent_skills_adapter.dart';

/// Antigravity IDE adapter.
///
/// Installs skills to `.agent/skills/<pkg>-<skill>/SKILL.md`.
class AntigravityAdapter extends AgentSkillsAdapter {
  AntigravityAdapter(String projectPath)
    : super(Ide.antigravity.skillsPath(projectPath));
}
