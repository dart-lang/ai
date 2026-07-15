import 'package:logging/logging.dart';

import '../agent.dart';
import 'agent_skills_adapter.dart';

/// Cline adapter (experimental).
///
/// Installs skills to `.cline/skills/<skill-name>/` per
/// [Cline skills](https://docs.cline.bot/customization/skills).
class ClineAdapter extends AgentSkillsAdapter {
  @override
  final Logger logger = Logger('ClineAdapter');

  ClineAdapter(String projectPath, {super.dialogSupport})
    : super(Agent.cline, Agent.cline.skillsPath(projectPath));
}
