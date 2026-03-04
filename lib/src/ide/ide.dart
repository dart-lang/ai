import 'dart:io';

import 'package:path/path.dart' as p;

/// Supported IDEs for skill installation.
enum Ide {
  cursor('cursor', '.cursor/skills'),
  antigravity('antigravity', '.agent/skills'),
  claude('claude', '.claude/rules'),
  copilot('copilot', '.github/instructions'),
  cline('cline', '.clinerules');

  final String cliName;

  /// Relative path from project root to the IDE's skills/rules directory.
  final String skillsRelativePath;

  const Ide(this.cliName, this.skillsRelativePath);

  /// Returns the absolute skills directory path for this IDE within [projectPath].
  String skillsPath(String projectPath) =>
      p.join(projectPath, skillsRelativePath);

  /// Whether this IDE is detected in the project at [projectPath].
  ///
  /// Copilot is excluded from auto-detection because its `.github/` marker
  /// directory is commonly used for CI/CD and other purposes. Use `--ide
  /// copilot` to install explicitly.
  bool isDetected(String projectPath) {
    return switch (this) {
      Ide.cursor => Directory(p.join(projectPath, '.cursor')).existsSync(),
      Ide.antigravity => Directory(p.join(projectPath, '.agent')).existsSync(),
      Ide.claude => Directory(p.join(projectPath, '.claude')).existsSync(),
      Ide.cline => Directory(p.join(projectPath, '.clinerules')).existsSync(),
      Ide.copilot => false,
    };
  }

  /// Parses a CLI name string into an [Ide].
  static Ide? fromCliName(String name) {
    for (final ide in Ide.values) {
      if (ide.cliName == name.toLowerCase()) return ide;
    }
    return null;
  }

  /// All valid CLI names as a list.
  static List<String> get cliNames => Ide.values.map((e) => e.cliName).toList();

  /// All valid CLI names as a comma-separated string.
  static String get validNames => cliNames.join(', ');
}

/// Detects which IDE is being used based on project directory markers.
class IdeDetector {
  const IdeDetector();

  /// Auto-detects a single IDE from project directory markers.
  ///
  /// Returns null if no IDE or multiple IDEs are detected.
  Ide? detect(String projectPath) {
    final detected = detectAll(projectPath);
    if (detected.length == 1) return detected.first;
    return null;
  }

  /// Detects all IDEs present in the project based on directory markers.
  List<Ide> detectAll(String projectPath) {
    return Ide.values.where((ide) => ide.isDetected(projectPath)).toList();
  }
}
