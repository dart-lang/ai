import 'package:path/path.dart' as p;
import 'package:skills/src/core/dialog_support.dart';

import 'adapters/claude_adapter.dart';
import 'adapters/cline_adapter.dart';
import 'adapters/copilot_adapter.dart';
import 'adapters/cursor_adapter.dart';
import 'adapters/custom_adapter.dart';
import 'adapters/generic_adapter.dart';
import 'adapters/opencode_adapter.dart';
import 'agent.dart';
import 'agent_adapter.dart';

/// Creates the appropriate [AgentAdapter] for the given [agent] and [projectPath].
AgentAdapter createAgentAdapter(
  Agent agent,
  String projectPath,
  DialogSupport? dialogSupport, {
  String? customInstallDir,
}) {
  return switch (agent) {
    Agent.cursor => CursorAdapter(projectPath, dialogSupport: dialogSupport),
    Agent.generic => GenericAdapter(projectPath, dialogSupport: dialogSupport),
    Agent.claude => ClaudeAdapter(projectPath, dialogSupport: dialogSupport),
    Agent.copilot => CopilotAdapter(projectPath, dialogSupport: dialogSupport),
    Agent.cline => ClineAdapter(projectPath, dialogSupport: dialogSupport),
    Agent.opencode => OpenCodeAdapter(
      projectPath,
      dialogSupport: dialogSupport,
    ),
    Agent.custom => CustomAdapter(
      _resolveCustomSkillsDirectory(projectPath, customInstallDir),
      dialogSupport: dialogSupport,
    ),
  };
}

String _resolveCustomSkillsDirectory(
  String projectPath,
  String? customInstallDir,
) {
  if (customInstallDir == null || customInstallDir.trim().isEmpty) {
    throw ArgumentError.notNull('customInstallDir');
  }
  return p.isAbsolute(customInstallDir)
      ? p.normalize(customInstallDir)
      : p.normalize(p.join(projectPath, customInstallDir));
}
