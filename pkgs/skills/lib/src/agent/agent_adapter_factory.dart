import 'adapters/claude_adapter.dart';
import 'adapters/cline_adapter.dart';
import 'adapters/copilot_adapter.dart';
import 'adapters/cursor_adapter.dart';
import 'adapters/generic_adapter.dart';
import 'adapters/opencode_adapter.dart';
import 'agent.dart';
import 'package:skills/src/core/dialog_support.dart';
import 'agent_adapter.dart';

/// Creates the appropriate [AgentAdapter] for the given [agent] and [projectPath].
AgentAdapter createAgentAdapter(
  Agent agent,
  String projectPath,
  DialogSupport? dialogSupport,
) {
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
  };
}
