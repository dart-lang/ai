import 'dart:io';

import 'package:skills/src/core/skill_scanner.dart';
import 'package:skills/src/ide/adapters/copilot_adapter.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  group('Given a CopilotAdapter', () {
    late CopilotAdapter adapter;

    setUp(() async {
      await d.dir('project', [
        d.dir('.github', [d.dir('instructions')]),
      ]).create();

      adapter = CopilotAdapter(d.path('project'));
    });

    group('and a scanned skill', () {
      late ScannedSkill skill;

      setUp(() async {
        await d.dir('copilot_pkg', [
          d.dir('skills', [
            d.dir('copilot_pkg-testing', [
              d.file('SKILL.md', '''
---
name: copilot_pkg-testing
description: Testing best practices.
---

# Testing

Write tests like this.
'''),
            ]),
          ]),
        ]).create();

        skill = ScannedSkill(
          packageName: 'copilot_pkg',
          skillName: 'copilot_pkg-testing',
          skillPath: d.path('copilot_pkg/skills/copilot_pkg-testing'),
        );
      });

      test('when installing then creates .instructions.md file in '
          '.github/instructions/', () async {
        await adapter.installSkill(skill);

        final file = File(
          d.path(
            'project/.github/instructions/'
            'copilot_pkg-testing.instructions.md',
          ),
        );
        expect(await file.exists(), isTrue);
      });

      test(
        'when installing then file has copilot frontmatter and body',
        () async {
          await adapter.installSkill(skill);

          final content = await File(
            d.path(
              'project/.github/instructions/'
              'copilot_pkg-testing.instructions.md',
            ),
          ).readAsString();

          expect(content, contains('applyTo: "**"'));
          expect(content, contains('<!-- managed by skills CLI -->'));
          expect(content, contains('# Testing'));
        },
      );
    });

    test('when removing then deletes the instructions file', () async {
      final target = File(
        d.path('project/.github/instructions/pkg-skill.instructions.md'),
      );
      await target.create(recursive: true);
      await target.writeAsString('content');

      adapter = CopilotAdapter(d.path('project'));
      await adapter.removeSkill('pkg-skill');

      expect(await target.exists(), isFalse);
    });
  });
}
