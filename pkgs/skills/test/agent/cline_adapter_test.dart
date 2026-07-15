import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:skills/src/core/skill_scanner.dart';
import 'package:skills/src/agent/adapters/cline_adapter.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  setUpAll(() {
    Logger.root.onRecord.listen((r) => printOnFailure(r.toString()));
  });

  group('Given a ClineAdapter', () {
    late ClineAdapter adapter;

    setUp(() async {
      await d.dir('project', [
        d.dir('.cline', [d.dir('skills')]),
      ]).create();

      adapter = ClineAdapter(d.path('project'));
    });

    group('and a scanned skill', () {
      late ScannedSkill skill;

      setUp(() async {
        await d.dir('cline_pkg', [
          d.dir('skills', [
            d.dir('cline_pkg-debugging', [
              d.file('SKILL.md', '''
---
name: cline_pkg-debugging
description: Debugging techniques.
---

# Debugging

Debugging steps.
'''),
            ]),
          ]),
        ]).create();

        skill = ScannedSkill(
          packageName: 'cline_pkg',
          skillName: 'cline_pkg-debugging',
          skillPath: d.path('cline_pkg/skills/cline_pkg-debugging'),
        );
      });

      test(
        'when installing then creates skill directory in .cline/skills/',
        () async {
          final name = (await adapter.installSkill(skill)).name;

          expect(name, equals('cline_pkg-debugging'));

          final installed = Directory(
            p.join(
              d.path('project'),
              '.cline',
              'skills',
              'cline_pkg-debugging',
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
            '.cline',
            'skills',
            'cline_pkg-debugging',
            'SKILL.md',
          ),
        ).readAsString();

        expect(content, contains('name: cline_pkg-debugging'));
        expect(content, contains('# Debugging'));
      });
    });

    test('when removing then deletes the skill directory', () async {
      await d.dir('project', [
        d.dir('.cline', [
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

      adapter = ClineAdapter(d.path('project'));
      await adapter.removeSkill('pkg-skill');

      expect(
        await Directory(
          p.join(d.path('project'), '.cline', 'skills', 'pkg-skill'),
        ).exists(),
        isFalse,
      );
    });
  });
}
