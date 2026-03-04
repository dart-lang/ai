import '../../models/skill_metadata.dart';
import '../ide.dart';
import 'rules_adapter.dart';

/// GitHub Copilot adapter.
///
/// Installs skills to `.github/instructions/<pkg>-<skill>.instructions.md`.
class CopilotAdapter extends RulesAdapter {
  CopilotAdapter(String projectPath)
    : super(
        skillsDirectory: Ide.copilot.skillsPath(projectPath),
        fileExtension: '.instructions.md',
        headerBuilder: _buildHeader,
      );

  static String _buildHeader(SkillMetadata metadata) {
    return '---\napplyTo: "**"\n---\n'
        '<!-- managed by skills CLI -->\n'
        '<!-- skill: ${metadata.name} -->\n\n';
  }
}
