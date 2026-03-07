import '../ide.dart';
import 'agent_skills_adapter.dart';

/// Cline adapter (experimental).
///
/// Installs skills to `.cline/skills/<skill-name>/` per
/// [Cline skills](https://docs.cline.bot/customization/skills).
class ClineAdapter extends AgentSkillsAdapter {
  ClineAdapter(String projectPath) : super(Ide.cline.skillsPath(projectPath));
}
