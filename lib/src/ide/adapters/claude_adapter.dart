import '../ide.dart';
import 'rules_adapter.dart';

/// Claude Code adapter.
///
/// Installs skills to `.claude/rules/<pkg>-<skill>.md`.
class ClaudeAdapter extends RulesAdapter {
  ClaudeAdapter(String projectPath)
    : super(
        skillsDirectory: Ide.claude.skillsPath(projectPath),
        fileExtension: '.md',
        headerBuilder: defaultManagedHeader,
      );
}
