import 'package:logging/logging.dart';

import '../ide.dart';
import 'agent_skills_adapter.dart';

/// GitHub Copilot adapter.
///
/// Installs skills to `.github/skills/<skill-name>/` per
/// [Copilot agent skills](https://docs.github.com/en/copilot/concepts/agents/about-agent-skills).
class CopilotAdapter extends AgentSkillsAdapter {
  @override
  final Logger logger = Logger('CopilotAdapter');

  CopilotAdapter(String projectPath, {super.dialogSupport})
    : super(Ide.copilot.skillsPath(projectPath));
}
