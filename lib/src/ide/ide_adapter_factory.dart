import 'adapters/antigravity_adapter.dart';
import 'adapters/claude_adapter.dart';
import 'adapters/cline_adapter.dart';
import 'adapters/copilot_adapter.dart';
import 'adapters/cursor_adapter.dart';
import 'ide.dart';
import 'ide_adapter.dart';

/// Creates the appropriate [IdeAdapter] for the given [ide] and [projectPath].
IdeAdapter createIdeAdapter(Ide ide, String projectPath) {
  return switch (ide) {
    Ide.cursor => CursorAdapter(projectPath),
    Ide.antigravity => AntigravityAdapter(projectPath),
    Ide.claude => ClaudeAdapter(projectPath),
    Ide.copilot => CopilotAdapter(projectPath),
    Ide.cline => ClineAdapter(projectPath),
  };
}
