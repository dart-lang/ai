import '../ide.dart';
import 'agent_skills_adapter.dart';

/// OpenCode adapter.
///
/// Installs skills to `.opencode/skills/<skill-name>/` per
/// [OpenCode skills](https://opencode.ai/docs/skills/).
class OpenCodeAdapter extends AgentSkillsAdapter {
  OpenCodeAdapter(String projectPath)
      : super(Ide.opencode.skillsPath(projectPath));
}
