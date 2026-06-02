import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:skills/src/core/skill_scanner.dart';
import 'package:skills/src/ide/adapters/opencode_adapter.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  setUpAll(() {
    Logger.root.onRecord.listen((r) => printOnFailure(r.toString()));
  });

  group('Given an OpenCodeAdapter', () {
    late OpenCodeAdapter adapter;

    setUp(() async {
      await d.dir('project', [
        d.dir('.opencode', [d.dir('skills')]),
      ]).create();

      adapter = OpenCodeAdapter(d.path('project'));
    });

    group('and a scanned skill', () {
      late ScannedSkill skill;

      setUp(() async {
        await d.dir('opencode_pkg', [
          d.dir('skills', [
            d.dir('opencode_pkg-code-review', [
              d.file('SKILL.md', '''
---
name: opencode_pkg-code-review
description: Reviews code.
---

# Code Review

Review guidelines here.
'''),
            ]),
          ]),
        ]).create();

        skill = ScannedSkill(
          packageName: 'opencode_pkg',
          skillName: 'opencode_pkg-code-review',
          skillPath: d.path('opencode_pkg/skills/opencode_pkg-code-review'),
        );
      });

      test(
        'when installing then creates skill directory in .opencode/skills/',
        () async {
          final name = await adapter.installSkill(skill);

          expect(name, equals('opencode_pkg-code-review'));

          final installed = Directory(
            p.join(
              d.path('project'),
              '.opencode',
              'skills',
              'opencode_pkg-code-review',
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
            '.opencode',
            'skills',
            'opencode_pkg-code-review',
            'SKILL.md',
          ),
        ).readAsString();

        expect(content, contains('name: opencode_pkg-code-review'));
        expect(content, contains('# Code Review'));
      });
    });

    test('when removing then deletes the skill directory', () async {
      await d.dir('project', [
        d.dir('.opencode', [
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

      adapter = OpenCodeAdapter(d.path('project'));
      await adapter.removeSkill('pkg-skill');

      expect(
        await Directory(
          p.join(d.path('project'), '.opencode', 'skills', 'pkg-skill'),
        ).exists(),
        isFalse,
      );
    });
  });
}
