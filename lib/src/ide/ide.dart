import 'dart:io';

import 'package:path/path.dart' as p;

/// Supported IDEs for skill installation.
///
/// The "generic" IDE uses `.agents/skills/`. Antigravity, Codex, and generic are
/// separate CLI options that all map here; only "generic" is stored in
/// skills_config.
enum Ide {
  cursor('cursor', '.cursor/skills'),
  generic('generic', '.agents/skills'),
  claude('claude', '.claude/skills'),
  copilot('copilot', '.github/skills'),
  cline('cline', '.cline/skills'),
  opencode('opencode', '.opencode/skills');

  final String cliName;

  /// Relative path from project root to the IDE's skills/rules directory.
  final String skillsRelativePath;

  const Ide(this.cliName, this.skillsRelativePath);

  /// Aliases that map to this IDE in the CLI (e.g. antigravity, codex → generic).
  List<String> get cliAliases => switch (this) {
    Ide.generic => ['antigravity', 'codex'],
    _ => [],
  };

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
      Ide.generic => Directory(p.join(projectPath, '.agents')).existsSync(),
      Ide.claude => Directory(p.join(projectPath, '.claude')).existsSync(),
      Ide.cline =>
        Directory(p.join(projectPath, '.cline')).existsSync() ||
            Directory(p.join(projectPath, '.clinerules')).existsSync(),
      Ide.copilot => false,
      Ide.opencode => Directory(p.join(projectPath, '.opencode')).existsSync(),
    };
  }

  /// Parses a CLI name string into an [Ide].
  /// Accepts canonical names and aliases (e.g. antigravity, codex → generic).
  static Ide? fromCliName(String name) {
    final lower = name.toLowerCase();
    for (final ide in Ide.values) {
      if (ide.cliName == lower) return ide;
      if (ide.cliAliases.contains(lower)) return ide;
    }
    return null;
  }

  /// All valid CLI names (canonical + aliases) for --ide and help.
  /// Sorted alphabetically with "generic" last.
  static List<String> get cliNames {
    final all = Ide.values.expand((e) => [e.cliName, ...e.cliAliases]).toList();
    all.sort((a, b) {
      if (a == 'generic') return 1;
      if (b == 'generic') return -1;
      return a.compareTo(b);
    });
    return all;
  }

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
