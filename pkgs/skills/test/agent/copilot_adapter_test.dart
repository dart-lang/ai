import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:skills/src/core/skill_scanner.dart';
import 'package:skills/src/agent/adapters/copilot_adapter.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  setUpAll(() {
    Logger.root.onRecord.listen((r) => printOnFailure(r.toString()));
  });

  group('Given a CopilotAdapter', () {
    late CopilotAdapter adapter;

    setUp(() async {
      await d.dir('project', [
        d.dir('.github', [d.dir('skills')]),
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

      test(
        'when installing then creates skill directory in .github/skills/',
        () async {
          final name = (await adapter.installSkill(skill)).name;

          expect(name, equals('copilot_pkg-testing'));

          final installed = Directory(
            p.join(
              d.path('project'),
              '.github',
              'skills',
              'copilot_pkg-testing',
            ),
          );
          expect(await installed.exists(), isTrue);
        },
      );

      test('when installing then SKILL.md is copied unchanged', () async {
        await adapter.installSkill(skill);

        final content = await File(
          p.join(
            d.path('project'),
            '.github',
            'skills',
            'copilot_pkg-testing',
            'SKILL.md',
          ),
        ).readAsString();

        expect(content, contains('name: copilot_pkg-testing'));
        expect(content, contains('# Testing'));
      });
    });

    test('when removing then deletes the skill directory', () async {
      await d.dir('project', [
        d.dir('.github', [
          d.dir('skills', [
            d.dir('pkg-skill', [
              d.file(
                'SKILL.md',
                '---\nname: pkg-skill\n'
                    'description: x\n---\nbody',
              ),
            ]),
          ]),
        ]),
      ]).create();

      adapter = CopilotAdapter(d.path('project'));
      await adapter.removeSkill('pkg-skill');

      expect(
        await Directory(
          p.join(d.path('project'), '.github', 'skills', 'pkg-skill'),
        ).exists(),
        isFalse,
      );
    });
  });
}
