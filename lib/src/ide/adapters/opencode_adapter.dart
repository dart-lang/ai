import 'package:logging/logging.dart';

import '../ide.dart';
import 'agent_skills_adapter.dart';

/// OpenCode adapter.
///
/// Installs skills to `.opencode/skills/<skill-name>/` per
/// [OpenCode skills](https://opencode.ai/docs/skills/).
class OpenCodeAdapter extends AgentSkillsAdapter {
  @override
  final Logger logger = Logger('OpenCodeAdapter');

  OpenCodeAdapter(String projectPath, {super.dialogSupport})
    : super(Ide.opencode.skillsPath(projectPath));
}
