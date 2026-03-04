import 'dart:io';

import 'package:skills/src/core/skill_scanner.dart';
import 'package:skills/src/ide/adapters/claude_adapter.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  group('Given a ClaudeAdapter', () {
    late ClaudeAdapter adapter;

    setUp(() async {
      await d.dir('project', [
        d.dir('.claude', [d.dir('rules')]),
      ]).create();

      adapter = ClaudeAdapter(d.path('project'));
    });

    group('and a scanned skill', () {
      late ScannedSkill skill;

      setUp(() async {
        await d.dir('claude_pkg', [
          d.dir('skills', [
            d.dir('claude_pkg-code-review', [
              d.file('SKILL.md', '''
---
name: claude_pkg-code-review
description: Reviews code.
---

# Code Review

Review guidelines here.
'''),
            ]),
          ]),
        ]).create();

        skill = ScannedSkill(
          packageName: 'claude_pkg',
          skillName: 'claude_pkg-code-review',
          skillPath: d.path('claude_pkg/skills/claude_pkg-code-review'),
        );
      });

      test('when installing then creates .md file in .claude/rules/', () async {
        await adapter.installSkill(skill);

        final ruleFile = File(
          d.path('project/.claude/rules/claude_pkg-code-review.md'),
        );
        expect(await ruleFile.exists(), isTrue);
      });

      test(
        'when installing then file contains skill body with header',
        () async {
          await adapter.installSkill(skill);

          final content = await File(
            d.path('project/.claude/rules/claude_pkg-code-review.md'),
          ).readAsString();

          expect(content, contains('<!-- managed by skills CLI -->'));
          expect(content, contains('# Code Review'));
          expect(content, contains('Review guidelines here.'));
        },
      );

      test(
        'when installing then YAML frontmatter is not in the output',
        () async {
          await adapter.installSkill(skill);

          final content = await File(
            d.path('project/.claude/rules/claude_pkg-code-review.md'),
          ).readAsString();

          expect(content, isNot(contains('---')));
        },
      );
    });

    test('when removing then deletes the rule file', () async {
      await d.file('project/.claude/rules/pkg-skill.md', 'content').create();

      adapter = ClaudeAdapter(d.path('project'));
      await adapter.removeSkill('pkg-skill');

      expect(
        await File(d.path('project/.claude/rules/pkg-skill.md')).exists(),
        isFalse,
      );
    });
  });
}
