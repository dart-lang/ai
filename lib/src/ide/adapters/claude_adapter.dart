import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/skill_scanner.dart';
import '../ide.dart';
import 'agent_skills_adapter.dart';

/// Claude Code adapter.
///
/// Installs skills to `.claude/skills/<skill-name>/` per
/// [Claude Code skills](https://code.claude.com/docs/en/skills).
class ClaudeAdapter extends AgentSkillsAdapter {
  ClaudeAdapter(String projectPath) : super(Ide.claude.skillsPath(projectPath));

  @override
  Future<String> installSkill(ScannedSkill skill) async {
    final name = await super.installSkill(skill);

    final skillMd = File(
      p.join(skillsDirectory, skill.skillName, 'SKILL.md'),
    );
    if (await skillMd.exists()) {
      var content = await skillMd.readAsString();
      if (!content.contains('user-invocable:')) {
        final closingIndex = content.indexOf('---', 3);
        if (closingIndex != -1) {
          content = '${content.substring(0, closingIndex)}'
              'user-invocable: false\n'
              '${content.substring(closingIndex)}';
          await skillMd.writeAsString(content);
        }
      }
    }

    return name;
  }
}
