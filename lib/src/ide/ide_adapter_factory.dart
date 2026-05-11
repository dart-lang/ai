import 'adapters/claude_adapter.dart';
import 'adapters/cline_adapter.dart';
import 'adapters/copilot_adapter.dart';
import 'adapters/cursor_adapter.dart';
import 'adapters/generic_adapter.dart';
import 'adapters/opencode_adapter.dart';
import 'ide.dart';
import 'package:skills/src/core/dialog_support.dart';
import 'ide_adapter.dart';

/// Creates the appropriate [IdeAdapter] for the given [ide] and [projectPath].
IdeAdapter createIdeAdapter(
    Ide ide, String projectPath, DialogSupport? dialogSupport) {
  return switch (ide) {
    Ide.cursor => CursorAdapter(projectPath),
    Ide.generic => GenericAdapter(projectPath, dialogSupport),
    Ide.claude => ClaudeAdapter(projectPath),
    Ide.copilot => CopilotAdapter(projectPath),
    Ide.cline => ClineAdapter(projectPath),
    Ide.opencode => OpenCodeAdapter(projectPath),
  };
}
