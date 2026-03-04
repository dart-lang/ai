import '../ide.dart';
import 'rules_adapter.dart';

/// Cline adapter.
///
/// Installs skills to `.clinerules/<pkg>-<skill>.md`.
class ClineAdapter extends RulesAdapter {
  ClineAdapter(String projectPath)
    : super(
        skillsDirectory: Ide.cline.skillsPath(projectPath),
        fileExtension: '.md',
        headerBuilder: defaultManagedHeader,
      );
}
