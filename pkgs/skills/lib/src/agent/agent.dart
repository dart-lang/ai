import 'dart:io';

import 'package:path/path.dart' as p;

/// Supported agents for skill installation.
///
/// The "generic" agent uses `.agents/skills/`. Antigravity, Codex, and generic are
/// separate CLI options that all map here; only "generic" is stored in
/// skills_config.
enum Agent {
  cursor('cursor', '.cursor/skills'),
  generic('generic', '.agents/skills'),
  claude('claude', '.claude/skills'),
  copilot('copilot', '.github/skills'),
  cline('cline', '.cline/skills'),
  opencode('opencode', '.opencode/skills');

  final String cliName;

  /// Relative path from project root to the agent's skills/rules directory.
  final String skillsRelativePath;

  const Agent(this.cliName, this.skillsRelativePath);

  /// Aliases that map to this agent in the CLI (e.g. antigravity, codex → generic).
  List<String> get cliAliases => switch (this) {
    Agent.generic => ['antigravity', 'codex'],
    _ => [],
  };

  /// Returns the absolute skills directory path for this agent within [projectPath].
  String skillsPath(String projectPath) =>
      p.join(projectPath, skillsRelativePath);

  /// Whether this agent is detected in the project at [projectPath].
  ///
  /// Copilot is excluded from auto-detection because its `.github/` marker
  /// directory is commonly used for CI/CD and other purposes. Use `--agent
  /// copilot` to install explicitly.
  bool isDetected(String projectPath) {
    return switch (this) {
      Agent.cursor => Directory(p.join(projectPath, '.cursor')).existsSync(),
      Agent.generic => Directory(p.join(projectPath, '.agents')).existsSync(),
      Agent.claude => Directory(p.join(projectPath, '.claude')).existsSync(),
      Agent.cline =>
        Directory(p.join(projectPath, '.cline')).existsSync() ||
            Directory(p.join(projectPath, '.clinerules')).existsSync(),
      Agent.copilot => false,
      Agent.opencode => Directory(
        p.join(projectPath, '.opencode'),
      ).existsSync(),
    };
  }

  /// Parses a CLI name string into an [Agent].
  /// Accepts canonical names and aliases (e.g. antigravity, codex → generic).
  static Agent? fromCliName(String name) {
    final lower = name.toLowerCase();
    for (final agent in Agent.values) {
      if (agent.cliName == lower) return agent;
      if (agent.cliAliases.contains(lower)) return agent;
    }
    return null;
  }

  /// All valid CLI names (canonical + aliases) for --agent and help.
  /// Sorted alphabetically with "generic" last.
  static List<String> get cliNames {
    final all = Agent.values
        .expand((e) => [e.cliName, ...e.cliAliases])
        .toList();
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

/// Detects which agent is being used based on project directory markers.
class AgentDetector {
  const AgentDetector();

  /// Auto-detects a single agent from project directory markers.
  ///
  /// Returns null if no agent or multiple agents are detected.
  Agent? detect(String projectPath) {
    final detected = detectAll(projectPath);
    if (detected.length == 1) return detected.first;
    return null;
  }

  /// Detects all agents present in the project based on directory markers.
  List<Agent> detectAll(String projectPath) {
    return Agent.values
        .where((agent) => agent.isDetected(projectPath))
        .toList();
  }
}
